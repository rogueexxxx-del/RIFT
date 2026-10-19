# Per-effect cost, measured deterministically.
#
# The app's own fps counter answers "is it slow", never "which effect is slow".
# With 15 shaders and costs that differ by 10x, that is the question worth
# answering, and the stereograph mode already proved a single shader can take
# the whole viewport down.
#
# Renders a fixed frame count through each effect and times it. Uses the EXPORT
# path on purpose: it runs as fast as the machine allows instead of pacing to a
# 60 Hz clock, so the number reflects the work rather than the vsync.
#
# This is THROUGHPUT. For stutter, run the app and read the "worst" figure in
# the top-right readout, which is the worst frame over a rolling window (the
# engine keeps p50/p95/p99/max). Use -Sweep to attribute cost inside a chain.
#
#   powershell -ExecutionPolicy Bypass -File tools\bench.ps1
#   powershell -ExecutionPolicy Bypass -File tools\bench.ps1 -Height 2160
param(
    [int]$Width  = 1920,
    [int]$Height = 1080,
    [int]$Seconds = 4,
    [string[]]$Effects = @(),
    [string]$BuildDir = "build-release",
    [string]$Config   = "Release",
    # Attribute cost INSIDE a chain. QRhi cannot timestamp individual passes,
    # so the cost of pass N is measured as (chain of N) minus (chain of N-1).
    # Answers "which effect in my stack is the expensive one" without PIX.
    [string[]]$Sweep = @()
)

$ErrorActionPreference = "Stop"
if ($Width -lt 2 -or $Height -lt 2 -or $Width % 2 -or $Height % 2 -or $Seconds -lt 1) {
    throw "Width and Height must be positive even numbers; Seconds must be positive"
}
$root = Split-Path -Parent $PSScriptRoot
$B    = Join-Path $root $BuildDir
$exe  = Join-Path $B "$Config\rift_shell.exe"
$work = Join-Path $B "bench"
$ff   = "D:\download\ffmpeg-master-latest-win64-lgpl-shared\ffmpeg-master-latest-win64-lgpl-shared\bin\ffmpeg.exe"
$probe = Join-Path (Split-Path $ff) "ffprobe.exe"

if (-not (Test-Path $exe)) { throw "no exe at $exe - build first" }
New-Item -ItemType Directory -Force $work | Out-Null

# Deployed layout means no QT_* env vars are needed; keep the fallbacks for a
# build that has not been staged yet.
$q = Join-Path $B "vcpkg_installed\x64-windows\Qt6"
if (-not (Test-Path (Join-Path (Split-Path $exe) "platforms\qwindows.dll")) -and
    (Test-Path $q)) {
    $env:QT_QPA_PLATFORM_PLUGIN_PATH = "$q\plugins\platforms"
    $env:QT_PLUGIN_PATH = "$q\plugins"
    $env:QML_IMPORT_PATH = "$q\qml"
    $env:PATH = (Join-Path $B "vcpkg_installed\x64-windows\bin") + ";" + $env:PATH
}

if ($Effects.Count -eq 0) {
    $Effects = @("ascii","halftone","dither","glitch","pixel_sort",
                 "noise_field","fracture","oscilloscope","datamosh",
                 "risograph","electron_scan")
}

# Broadband audio and a tonally rich source: a flat colour would make every
# effect look equally cheap, and silence makes the scopes do no work at all.
$src = Join-Path $work "src-${Width}x${Height}-${Seconds}s.mp4"
$aud = Join-Path $work "aud-${Seconds}s.wav"
if (-not (Test-Path $src)) {
    & $ff -y -v error -f lavfi -i "mandelbrot=size=${Width}x${Height}:rate=60" `
        -t $Seconds -pix_fmt yuv420p $src
    if ($LASTEXITCODE -ne 0) { throw "source generation failed" }
}
if (-not (Test-Path $aud)) {
    # ${Seconds} braces are load-bearing: "$Seconds:r" parses as a scoped
    # variable reference in PowerShell, which silently produced "d==48000" and
    # generated no audio at all, so every effect was benchmarked on silence.
    & $ff -y -v error -f lavfi -i "anoisesrc=c=pink:d=${Seconds}:r=48000:a=0.5" `
        -af "volume=6" $aud
    if ($LASTEXITCODE -ne 0) { throw "audio generation failed" }
}

# Fail loudly if a probe file is missing. The app does not stop when its input
# is absent -- it just renders nothing reactive -- so the run completes and the
# numbers look plausible while measuring something else entirely. That is
# exactly what happened when the audio filter string was malformed.
foreach ($f in @($src, $aud)) {
    if (-not (Test-Path $f)) { throw "probe input missing: $f" }
}

$frames = $Seconds * 60
"RIFT bench - ${Width}x${Height}, $frames frames per effect"
"exe: $exe"
""
$rows = @()

foreach ($e in $Effects) {
    $out = Join-Path $work "$e.mp4"
    if (Test-Path $out) { Remove-Item $out -Force }

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process -FilePath $exe -WorkingDirectory $B -NoNewWindow -PassThru `
         -ArgumentList @("--clip", ('"{0}"' -f $src), "--audio", ('"{0}"' -f $aud), "--chain", $e,
                         "--export-width", "$Width", "--export-height", "$Height",
                         "--play", "--export", ('"{0}"' -f $out)) `
         -RedirectStandardError (Join-Path $work "err.txt") `
         -RedirectStandardOutput (Join-Path $work "out.txt")
    if (-not $p.WaitForExit(300000)) { $p.Kill(); $rows += [pscustomobject]@{
        Effect = $e; Sec = "TIMEOUT"; FPS = 0; MsPerFrame = 0 }; continue }
    $sw.Stop()
    if ($p.ExitCode -ne 0) { throw "export process failed: $e (exit $($p.ExitCode))" }

    if (-not (Test-Path $out)) {
        $rows += [pscustomobject]@{ Effect = $e; Sec = "FAILED"; FPS = 0; MsPerFrame = 0 }
        continue
    }
    $actual = & $probe -v error -select_streams v:0 -show_entries stream=width,height,nb_frames `
        -of default=noprint_wrappers=1 $out
    if ($LASTEXITCODE -ne 0 -or $actual -notcontains "width=$Width" -or
        $actual -notcontains "height=$Height" -or $actual -notcontains "nb_frames=$frames") {
        throw "unexpected export dimensions or frame count: $out ($actual)"
    }
    # Startup is a fixed overhead on every run and is not what is being
    # compared, but it is reported so a suspiciously small delta is visible.
    $sec = $sw.Elapsed.TotalSeconds
    $rows += [pscustomobject]@{
        Effect     = $e
        Sec        = [math]::Round($sec, 2)
        FPS        = [math]::Round($frames / $sec, 1)
        MsPerFrame = [math]::Round($sec * 1000 / $frames, 2)
    }
    "{0,-16} {1,7:N2}s  {2,7:N1} fps  {3,7:N2} ms/frame" -f `
        $e, $sec, ($frames / $sec), ($sec * 1000 / $frames)
    if ($env:RIFT_EXPORT_PROFILE) {
        Get-Content (Join-Path $work "err.txt") |
            Select-String '^\[export profile\]' | Select-Object -Last 1
    }
}

if ($Sweep.Count -gt 1) {
    ""
    "=== chain sweep: per-pass cost by differencing ==="
    $prev = 0.0
    for ($n = 1; $n -le $Sweep.Count; $n++) {
        $chain = ($Sweep[0..($n - 1)]) -join ","
        $out = Join-Path $work "sweep$n.mp4"
        if (Test-Path $out) { Remove-Item $out -Force }
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $p = Start-Process -FilePath $exe -WorkingDirectory $B -NoNewWindow -PassThru `
             -ArgumentList @("--clip", ('"{0}"' -f $src), "--audio", ('"{0}"' -f $aud), "--chain", $chain,
                             "--export-width", "$Width", "--export-height", "$Height",
                             "--play", "--export", ('"{0}"' -f $out)) `
             -RedirectStandardError (Join-Path $work "err.txt") `
             -RedirectStandardOutput (Join-Path $work "out.txt")
        if (-not $p.WaitForExit(300000)) { $p.Kill(); "  chain $n TIMEOUT"; continue }
        $sw.Stop()
        if ($p.ExitCode -ne 0 -or -not (Test-Path $out)) {
            throw "chain export failed: $chain (exit $($p.ExitCode))"
        }
        $actual = & $probe -v error -select_streams v:0 -show_entries stream=width,height,nb_frames `
            -of default=noprint_wrappers=1 $out
        if ($LASTEXITCODE -ne 0 -or $actual -notcontains "width=$Width" -or
            $actual -notcontains "height=$Height" -or $actual -notcontains "nb_frames=$frames") {
            throw "unexpected chain export dimensions or frame count: $out ($actual)"
        }
        $ms = $sw.Elapsed.TotalSeconds * 1000 / $frames
        # The first entry carries all the fixed overhead (startup, decode,
        # encode), so only the DELTAS are meaningful as per-pass costs.
        $delta = if ($n -eq 1) { [double]::NaN } else { $ms - $prev }
        "{0,-16} chain of {1}: {2,7:N2} ms/frame   added {3}" -f `
            $Sweep[$n - 1], $n, $ms,
            $(if ([double]::IsNaN($delta)) { "(baseline)" }
              else { "{0:N2} ms" -f $delta })
        $prev = $ms
    }
}

""
"=== slowest first ==="
$rows | Sort-Object MsPerFrame -Descending | Format-Table -AutoSize
$csv = Join-Path $root "bench-$Width x$Height.csv".Replace(" ", "")
$rows | Export-Csv -NoTypeInformation $csv
"saved: $csv"
"NOTE: elapsed time includes app startup and shutdown. Use RIFT_EXPORT_PROFILE=1"
"      for render, readback, and encode time per frame."
