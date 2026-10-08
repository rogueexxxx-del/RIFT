# Prove the staged build is self-contained, WITHOUT a second machine.
#
# Running the app here can never prove this: the dev box has Qt, FFmpeg and the
# MSVC runtime installed system-wide, so a dependency missing from dist/ still
# resolves from System32 and everything looks fine. It then dies on the first
# tester's PC with "the code execution cannot proceed because X.dll was not
# found" and no other clue.
#
# So instead of running it, walk the whole import graph statically. Every DLL
# imported by anything in dist/ must be EITHER bundled in dist/ OR a genuine
# Windows OS library. Anything else is a dependency that only works here.
#
#   powershell -ExecutionPolicy Bypass -File packaging\check_deps.ps1
param([string]$Dist = "")

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if (-not $Dist) { $Dist = Join-Path $root "dist" }
if (-not (Test-Path $Dist)) { throw "no staged build at $Dist" }

$dumpbin = Get-ChildItem "$env:ProgramFiles\Microsoft Visual Studio" -Recurse `
           -Filter dumpbin.exe -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -match "Hostx64\\x64" } |
           Select-Object -First 1 -ExpandProperty FullName
if (-not $dumpbin) { throw "dumpbin.exe not found - needs Visual Studio Build Tools" }

# The C/C++ runtime is the trap this check exists for. These names DO exist in
# System32 on any developer machine, so a "does it exist in System32" test would
# wave them through -- and they are exactly what a clean Windows install lacks.
# They must be bundled, never inherited.
$mustBundle = @(
    "msvcp140.dll", "msvcp140_1.dll", "msvcp140_2.dll", "msvcp140_atomic_wait.dll",
    "msvcp140_codecvt_ids.dll", "vcruntime140.dll", "vcruntime140_1.dll",
    "vcruntime140_threads.dll", "concrt140.dll", "vccorlib140.dll"
)

# Everything shipped, indexed by lowercase filename.
$bundled = @{}
Get-ChildItem $Dist -Recurse -Include *.dll, *.exe |
    ForEach-Object { $bundled[$_.Name.ToLower()] = $_.FullName }
"scanning {0} binaries in {1}" -f $bundled.Count, $Dist

$sys = Join-Path $env:SystemRoot "System32"
$missing = @{}
$checked = 0

foreach ($bin in $bundled.Values) {
    $checked++
    $out = & $dumpbin /dependents $bin 2>$null
    foreach ($line in $out) {
        if ($line -notmatch '^\s{4}(\S+\.dll)\s*$') { continue }
        $dep = $matches[1].ToLower()

        if ($bundled.ContainsKey($dep)) { continue }          # shipped: fine

        if ($mustBundle -contains $dep) {                     # runtime: must ship
            $missing[$dep] = "C/C++ runtime - NOT bundled (works here only because System32 has it)"
            continue
        }
        # Windows API sets and anything genuinely part of the OS.
        if ($dep -like "api-ms-win-*" -or $dep -like "ext-ms-*") { continue }
        if (Test-Path (Join-Path $sys $dep)) { continue }      # OS library: fine

        $missing[$dep] = "not in dist/ and not a Windows system DLL"
    }
}

""
"checked $checked binaries"
if ($missing.Count -eq 0) {
    "PASS - every dependency is either bundled or part of Windows."
    "       The staged build is self-contained."
    exit 0
}
"FAIL - {0} dependency/ies would be missing on a clean machine:" -f $missing.Count
foreach ($k in ($missing.Keys | Sort-Object)) { "  {0,-32} {1}" -f $k, $missing[$k] }
exit 1
