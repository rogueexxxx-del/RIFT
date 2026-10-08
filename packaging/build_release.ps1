# Produce a shippable RIFT: Release build -> staged dist -> installer.
#
# Everything during development has been Debug, which links the debug Qt DLLs
# and cannot be redistributed. This is a separate build directory on purpose:
# reconfiguring build-full as Release would force vcpkg to rebuild Qt again.
#
#   powershell -ExecutionPolicy Bypass -File packaging\build_release.ps1
#
# Add -Installer to also run Inno Setup (needs iscc.exe on PATH).
param(
    [switch]$Installer,
    [switch]$Zip,
    [string]$FfmpegDir = "D:/download/ffmpeg-master-latest-win64-lgpl-shared/ffmpeg-master-latest-win64-lgpl-shared",
    # Without the vcpkg toolchain CMake cannot see Qt at all and configure dies
    # on find_package(Qt6). build-full gets it from its cached CMakeCache; a
    # fresh build directory has to be told.
    [string]$VcpkgToolchain = "D:/vcpkg/scripts/buildsystems/vcpkg.cmake",
    [string]$Triplet = "x64-windows"
)

$ErrorActionPreference = "Stop"
$CM    = "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
$root  = Split-Path -Parent $PSScriptRoot
$build = Join-Path $root "build-release"
$dist  = Join-Path $root "dist"

# A running instance holds the DLLs the build is about to overwrite, and MSVC
# reports that as a confusing LNK1168 rather than "the app is open".
Get-Process | Where-Object { $_.ProcessName -like "*rift*" } |
    ForEach-Object { try { $_.Kill() } catch {} }

Write-Host "=== configure (Release) ===" -ForegroundColor Cyan
if (-not (Test-Path $VcpkgToolchain)) { throw "vcpkg toolchain not at $VcpkgToolchain" }

# CMake applies CMAKE_TOOLCHAIN_FILE only on the FIRST configure of a build
# directory; afterwards the cached value wins and the flag is silently ignored.
# So a build dir left behind by a failed configure keeps failing the same way
# no matter what is passed. Wipe it unless its cache already names the right
# toolchain.
$cache = Join-Path $build "CMakeCache.txt"
if (Test-Path $cache) {
    # Test that vcpkg actually RAN, not that the variable is present. Passing
    # -DCMAKE_TOOLCHAIN_FILE to a directory that already has a cache writes the
    # variable but does NOT apply the toolchain - CMake honours it only on a
    # directory's first configure. So the cache can name the toolchain while
    # Qt was never found, and checking the variable reports a healthy cache
    # that fails identically on every retry. vcpkg_installed only exists if the
    # toolchain really took effect.
    $cached = (Select-String -Path $cache -Pattern "^CMAKE_TOOLCHAIN_FILE" |
               Select-Object -First 1).Line
    $applied = Test-Path (Join-Path $build "vcpkg_installed")
    if (-not $applied -or -not $cached -or
        $cached -notmatch [regex]::Escape($VcpkgToolchain)) {
        "stale cache (vcpkg never ran) - wiping $build"
        Remove-Item $build -Recurse -Force
    }
}
& $CM -S $root -B $build `
    -DCMAKE_TOOLCHAIN_FILE="$VcpkgToolchain" `
    -DVCPKG_TARGET_TRIPLET="$Triplet" `
    -DCMAKE_BUILD_TYPE=Release `
    -DRIFT_WITH_RHI=ON -DRIFT_WITH_AUDIO=ON -DRIFT_WITH_FFMPEG=ON `
    -DRIFT_FFMPEG_DIR="$FfmpegDir"
if ($LASTEXITCODE -ne 0) { throw "configure failed" }

Write-Host "=== shaders ===" -ForegroundColor Cyan
& $CM --build $build --target rift_shaders_all --config Release
if ($LASTEXITCODE -ne 0) { throw "shader build failed" }

Write-Host "=== build ===" -ForegroundColor Cyan
# NOT --parallel. vcpkg runs a `z-applocal` post-build step per target that
# copies the dependent DLLs next to that target. Every target here shares one
# output directory, so building them concurrently has several processes copying
# the SAME Qt DLLs to the SAME path at once; they collide and the step exits 1
# with no message beyond MSB3073. Serial costs a few minutes and is reliable.
& $CM --build $build --config Release
if ($LASTEXITCODE -ne 0) { throw "build failed" }

Write-Host "=== stage (runs windeployqt) ===" -ForegroundColor Cyan
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
& $CM --install $build --config Release --prefix $dist
if ($LASTEXITCODE -ne 0) { throw "install failed" }

# ── Qt runtime ──
# vcpkg's qtbase does not ship windeployqt unless its "windeployqt" feature is
# enabled, and turning that on means rebuilding qtbase (hours). Everything it
# would copy is already on disk, so stage it directly:
#   * Qt DLLs      - vcpkg's applocal post-build step already put them beside
#                    the exe in the build tree
#   * plugins      - platforms/ is mandatory (no platform plugin, no window);
#                    imageformats and styles are needed by the QML shell
#   * QML modules  - the whole qml tree; pruning it to the imported modules is
#                    an optimisation, and a missing module is a silent failure
# The check at the end is what makes this trustworthy: it runs the app from the
# staged folder with a cleared environment.
Write-Host "=== stage Qt runtime ===" -ForegroundColor Cyan
$vcpkgQt = Join-Path $build (Join-Path "vcpkg_installed" (Join-Path $Triplet "Qt6"))
# EVERY runtime DLL vcpkg installed, not just the ones linked into the exe.
# QML plugins are loaded at runtime, so their libraries (Qt6QuickControls2Basic,
# Qt6QuickTemplates2, Qt6QuickLayouts ...) are not dependencies of the exe and
# applocal never copies them. Missing them fails at STARTUP, not at link time,
# with "The specified module could not be found" naming the plugin rather than
# the library it wanted. The non-Qt DLLs here (libpng, pcre2, zlib, harfbuzz,
# double-conversion, md4c) are Qt's own dependencies and are equally required.
$vcpkgBin = Join-Path $build (Join-Path "vcpkg_installed" (Join-Path $Triplet "bin"))
Copy-Item (Join-Path $vcpkgBin "*.dll") $dist -Force
Copy-Item (Join-Path $build "Release\*.dll") $dist -Force
foreach ($plug in @("platforms", "imageformats", "styles", "iconengines")) {
    $srcPlug = Join-Path $vcpkgQt "plugins\$plug"
    if (Test-Path $srcPlug) {
        New-Item -ItemType Directory -Force (Join-Path $dist $plug) | Out-Null
        Copy-Item "$srcPlug\*.dll" (Join-Path $dist $plug) -Force
    }
}
$qmlSrc = Join-Path $vcpkgQt "qml"
if (Test-Path $qmlSrc) {
    Copy-Item $qmlSrc $dist -Recurse -Force
} else {
    Write-Warning "no QML modules at $qmlSrc - the app will not start"
}
# Tell Qt where the plugins are relative to the exe, so no environment
# variables are needed on the target machine.
@"
[Paths]
Prefix = .
Plugins = .
Qml2Imports = qml
"@ | Set-Content (Join-Path $dist "qt.conf") -Encoding ascii

# The MSVC runtime. Qt itself imports msvcp140 / vcruntime140, so this is not
# optional - but it is invisible to the smoke test below, because THIS machine
# has the redistributable in System32 and always will. A tester without Visual
# Studio gets "the code execution cannot proceed because VCRUNTIME140.dll was
# not found" and nothing else. Copied from the Redist tree, which is the
# licensed route for shipping these; System32 copies are not redistributable.
Write-Host "=== stage MSVC runtime ===" -ForegroundColor Cyan
# vswhere is the supported way to find a Visual Studio install; hardcoding
# "18\Community" breaks on any other edition or version, and writing that path
# by hand has already been mangled twice by escaping.
$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
$crt = $null
if (Test-Path $vswhere) {
    $vsRoot = & $vswhere -latest -products * -property installationPath
    if ($vsRoot) {
        $redist = Join-Path $vsRoot "VC\Redist\MSVC"
        if (Test-Path $redist) {
            $crt = Get-ChildItem $redist -Recurse -Directory `
                       -Filter "Microsoft.VC*.CRT" -ErrorAction SilentlyContinue |
                   Where-Object { $_.FullName -like "*\x64\*" } |
                   Select-Object -First 1
        }
    }
}
if ($crt) {
    Copy-Item (Join-Path $crt.FullName "*.dll") $dist -Force
    "copied {0} CRT DLLs from {1}" -f `
        (Get-ChildItem $crt.FullName -Filter *.dll).Count, $crt.FullName
} else {
    Write-Warning "VC redist not found - the portable build will fail on any machine without Visual Studio"
}

Write-Host "=== staged contents ===" -ForegroundColor Cyan
"exe:      {0}"        -f (Test-Path "$dist\rift_shell.exe")
"shaders:  {0} files"  -f (Get-ChildItem "$dist\shaders" -ErrorAction SilentlyContinue).Count
"fonts:    {0} files"  -f (Get-ChildItem "$dist\fonts"   -ErrorAction SilentlyContinue).Count
"qt dlls:  {0}"        -f (Get-ChildItem "$dist\Qt6*.dll" -ErrorAction SilentlyContinue).Count
"platforms:{0}"        -f (Get-ChildItem "$dist\platforms" -ErrorAction SilentlyContinue).Count
"imageformats: {0}"    -f (($(Get-ChildItem "$dist\imageformats" -ErrorAction SilentlyContinue)).Name -join ", ")
"avcodec:  {0}"        -f ((Get-ChildItem "$dist\avcodec*.dll" -ErrorAction SilentlyContinue).Name -join ", ")
"total:    {0:N1} MB"  -f ((Get-ChildItem $dist -Recurse -File | Measure-Object Length -Sum).Sum / 1MB)

# ── does the staged folder actually run? ──
# The only check that means anything. This machine has Qt, FFmpeg and the MSVC
# runtime installed system-wide, so a missing dependency still works locally
# unless the environment is cleared first. Qt env vars are wiped and PATH is
# reduced to the system directories, which is what a tester's machine looks
# like. It still cannot prove the MSVC runtime ships correctly -- that needs a
# second machine.
Write-Host "=== smoke test the staged build ===" -ForegroundColor Cyan
$probe = Join-Path $dist "_probe.mp4"
$clean = @{
    QT_QPA_PLATFORM_PLUGIN_PATH = $null; QT_PLUGIN_PATH = $null
    QML_IMPORT_PATH = $null; QML2_IMPORT_PATH = $null
    QT_FORCE_STDERR_LOGGING = "1"; QT_ASSUME_STDERR_HAS_CONSOLE = "1"
    PATH = "$env:SystemRoot\system32;$env:SystemRoot"
}
$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = Join-Path $dist "rift_shell.exe"
$psi.Arguments = '--chain ascii --export "' + $probe + '"'
$psi.WorkingDirectory = $dist
$psi.UseShellExecute = $false
$psi.RedirectStandardError = $true
foreach ($k in $clean.Keys) {
    if ($null -eq $clean[$k]) { [void]$psi.EnvironmentVariables.Remove($k) }
    else { $psi.EnvironmentVariables[$k] = $clean[$k] }
}
$proc = [Diagnostics.Process]::Start($psi)
$err = $proc.StandardError.ReadToEnd()
if (-not $proc.WaitForExit(180000)) { $proc.Kill() }

if (Test-Path $probe) {
    "PASS - staged build renders with no Qt environment set ({0:N0} bytes)" -f `
        (Get-Item $probe).Length
    Remove-Item $probe -Force
    # Checked by PRESENCE, not by running: this machine loads the CRT from
    # System32 whether or not it is staged, so the run above cannot detect it.
    foreach ($need in @("vcruntime140.dll", "vcruntime140_1.dll", "msvcp140.dll")) {
        if (-not (Test-Path (Join-Path $dist $need))) {
            throw "$need missing from dist - it would fail on a machine without Visual Studio"
        }
    }
    "PASS - MSVC runtime staged"
} else {
    Write-Warning "FAIL - staged build did not render. Deployment is incomplete."
    if ($err) { $err.Trim() -split "`n" | Select-Object -Last 8 }
    throw "staged build is not runnable"
}

# Static proof that dist/ is self-contained. The run above cannot establish
# this: every dependency resolves on THIS machine whether or not it was staged,
# because Qt, FFmpeg and the MSVC runtime are installed system-wide here. This
# walks the whole import graph instead and fails if anything would be missing
# on a clean Windows install.
Write-Host "=== dependency closure ===" -ForegroundColor Cyan
& (Join-Path $PSScriptRoot "check_deps.ps1") -Dist $dist
if ($LASTEXITCODE -ne 0) { throw "dist is not self-contained - see above" }

if ($Zip) {
    # A zip is the least friction for testers: no installer, no admin prompt,
    # unpack and run. Same staged folder the installer packages.
    # NOT $zip: that is the -Zip switch parameter, and assigning a string to a
    # [switch] throws a type-conversion error.
    $zipPath = Join-Path $root ("RIFT-portable-" +
                                (Get-Date -Format "yyyyMMdd") + ".zip")
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path "$dist\*" -DestinationPath $zipPath -CompressionLevel Optimal
    "portable zip: {0}  ({1:N1} MB)" -f $zipPath, ((Get-Item $zipPath).Length / 1MB)
}

if ($Installer) {
    Write-Host "=== installer ===" -ForegroundColor Cyan
    # winget installs Inno Setup per-user by default, NOT into Program Files,
    # so check LOCALAPPDATA too before giving up.
    $iscc = (Get-Command iscc.exe -ErrorAction SilentlyContinue).Source
    foreach ($cand in @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
                        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
                        "$env:ProgramFiles\Inno Setup 6\ISCC.exe")) {
        if (-not $iscc -and (Test-Path $cand)) { $iscc = $cand }
    }
    if (-not (Test-Path $iscc)) {
        Write-Warning "Inno Setup not found - skipping. Get it from jrsoftware.org."
    } else {
        & $iscc "/DStageDir=$dist" (Join-Path $PSScriptRoot "rift.iss")
    }
}

Write-Host "=== DONE ===" -ForegroundColor Green
