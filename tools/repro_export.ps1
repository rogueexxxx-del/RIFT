# RIFT Export Reproduction Script (3-second export per effect)
param(
    [string]$BuildDir = "build-release",
    [string]$Config   = "Release",
    [string[]]$Effects = @()
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$B    = Join-Path $root $BuildDir
$exe  = Join-Path $B "$Config\rift_shell.exe"
$work = Join-Path $env:TEMP "rift_repro"
$ff   = "D:\download\ffmpeg-master-latest-win64-lgpl-shared\ffmpeg-master-latest-win64-lgpl-shared\bin\ffmpeg.exe"

if (-not (Test-Path $exe)) {
    # Check dist fallback
    $distExe = Join-Path $root "dist\rift_shell.exe"
    if (Test-Path $distExe) { $exe = $distExe; $B = Join-Path $root "dist" }
    else { throw "no exe found at $exe or $distExe" }
}

New-Item -ItemType Directory -Force $work | Out-Null

$q = Join-Path $root "build-release\vcpkg_installed\x64-windows\Qt6"
if (Test-Path $q) {
    $env:QT_QPA_PLATFORM_PLUGIN_PATH = "$q\plugins\platforms"
    $env:QT_PLUGIN_PATH = "$q\plugins"
    $env:QML_IMPORT_PATH = "$q\qml"
    $env:PATH = (Join-Path $root "build-release\vcpkg_installed\x64-windows\bin") + ";" + $env:PATH
}

$src = Join-Path $work "src.mp4"
$aud = Join-Path $work "aud.wav"
if (-not (Test-Path $src)) {
    & $ff -y -v error -f lavfi -i "testsrc=size=1920x1080:rate=60" -t 3 -pix_fmt yuv420p $src
}
if (-not (Test-Path $aud)) {
    & $ff -y -v error -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=3" $aud
}

if ($Effects.Count -eq 0) {
    $Effects = @("oscilloscope", "tunnel", "kaleido", "feedback", "ascii", "glitch", "blur", "dither")
}

Write-Host "Running 3s export repro across effects using: $exe"

foreach ($e in $Effects) {
    $out = Join-Path $work "$e.mp4"
    if (Test-Path $out) { Remove-Item $out -Force }
    $errFile = Join-Path $work "$e.err.txt"
    $outFile = Join-Path $work "$e.out.txt"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.WorkingDirectory = (Split-Path $exe)
    $psi.Arguments = "--clip `"$src`" --audio `"$aud`" --chain $e --play --export `"$out`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardOutput = $true
    $psi.EnvironmentVariables["QT_QPA_PLATFORM_PLUGIN_PATH"] = $env:QT_QPA_PLATFORM_PLUGIN_PATH
    $psi.EnvironmentVariables["QT_PLUGIN_PATH"] = $env:QT_PLUGIN_PATH
    $psi.EnvironmentVariables["QML_IMPORT_PATH"] = $env:QML_IMPORT_PATH
    $psi.EnvironmentVariables["PATH"] = (Join-Path $root "build-release\vcpkg_installed\x64-windows\bin") + ";" + (Split-Path $exe) + ";" + $env:PATH

    $proc = [System.Diagnostics.Process]::Start($psi)
    $errTask = $proc.StandardError.ReadToEndAsync()
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $exited = $proc.WaitForExit(35000)

    if (-not $exited) {
        $proc.Kill()
        Write-Host "[$e] TIMEOUT/HANG" -ForegroundColor Red
        continue
    }

    $errText = $errTask.Result
    $outText = $outTask.Result
    [System.IO.File]::WriteAllText($errFile, $errText)
    [System.IO.File]::WriteAllText($outFile, $outText)

    if (-not (Test-Path $out) -or (Get-Item $out).Length -lt 2048) {
        $shortErr = if ($errText.Length -gt 0) { ($errText -split "`n")[-2..-1] -join " " } else { "" }
        Write-Host "[$e] FAILED (no valid output file): $shortErr" -ForegroundColor Red
        continue
    }

    # Extract sample middle frame and test pixel stats
    $frameImg = Join-Path $work "$e.frame.png"
    if (Test-Path $frameImg) { Remove-Item $frameImg -Force }
    & $ff -y -v error -ss 00:00:01.5 -i $out -vframes 1 $frameImg

    if (-not (Test-Path $frameImg)) {
        Write-Host "[$e] FAILED (cannot decode frame)" -ForegroundColor Red
    } else {
        $sz = (Get-Item $out).Length
        Write-Host "[$e] OK (exported $sz bytes, frame captured)" -ForegroundColor Green
    }
}
