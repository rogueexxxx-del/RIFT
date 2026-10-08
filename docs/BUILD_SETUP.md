# Build Environment Setup (Windows)

Everything needed to compile the C++ engine + run the parity/decode gates.
One-time setup, ~60-90 min mostly download time.

## 1. Toolchain
- **Visual Studio 2022** (Community is fine) with workload:
  *Desktop development with C++* → includes MSVC v143, Windows 11 SDK, CMake.
  Verify: open *x64 Native Tools Command Prompt for VS 2022*, run `cl` → prints version.
- **Git** (for vcpkg).
- **Python 3.11** already installed (used by the offline tools).

## 2. vcpkg (dependency manager)
```
git clone https://github.com/microsoft/vcpkg C:\vcpkg
C:\vcpkg\bootstrap-vcpkg.bat
setx VCPKG_ROOT C:\vcpkg
```
Pin the baseline in `vcpkg.json` (replace `REPLACE_WITH_VCPKG_COMMIT`):
```
cd C:\vcpkg && git rev-parse HEAD      # copy the hash into vcpkg.json builtin-baseline
```

## 3. Dependencies (manifest mode - auto-installed at configure)
`vcpkg.json` already lists them. Configure triggers the install:
- `qtbase[gui]` - QRhi + windowing (big; ~30-40 min first build)
- `qtshadertools` - `qsb` (GLSL→SPIR-V/HLSL)
- `ffmpeg[avcodec,avformat,swscale,nvcodec]` - decode/encode + NVENC/NVDEC
- `pffft` - real-time FFT (P3)
- `miniaudio` - playback (P3)

> FFmpeg licensing: default vcpkg build is LGPL (dynamic). NVENC/NVDEC via the
> nvcodec feature uses NVIDIA headers (permissible). Keep dynamic-linked.

## 4. Configure + build
From the repo root (`RIFT_engine/`), in the VS x64 native prompt:
```
cmake -B build -S . -G Ninja ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_TOOLCHAIN_FILE=%VCPKG_ROOT%/scripts/buildsystems/vcpkg.cmake ^
  -DRIFT_WITH_RHI=ON -DRIFT_WITH_FFMPEG=ON
cmake --build build --config Release
```
First configure downloads+builds Qt/FFmpeg via vcpkg (slow, once). Later builds
are fast.

## 5. Run gates
```
# generate golden references (Python - no build needed)
python tools/golden_dump.py --image ..\RIFT\texture.png --audio ..\RIFT\track.mp3 ^
    --shader ascii --frames 0,60,120,300 --out testdata\gold
python tools\analyze\analyze.py ..\RIFT\track.mp3 testdata\gold.analysis

# smoke + parity
ctest --test-dir build --output-on-failure
```
- `smoke` - C ABI surface (always)
- `parity` - check A channels atol 1e-4; check B frames ≤2 LSB (RHI build)

## 6. Deploy (later, P6)
```
windeployqt --release build\rift_app.exe
```
Then package `build\` folder with an Inno Setup script → single installer.

## Common issues
| Symptom | Fix |
|---|---|
| `cl not found` | use the *x64 Native Tools* prompt, not plain cmd |
| Qt build fails OOM | close apps; vcpkg Qt needs ~8 GB RAM + ~20 GB disk |
| `qsb not found` | ensure `qtshadertools` installed; it's a vcpkg host tool |
| NVENC missing | non-NVIDIA GPU → engine falls back to libx264 (already handled) |
| linker: avcodec unresolved | confirm `-DRIFT_WITH_FFMPEG=ON` + FFMPEG found by find_package |

## Minimal path (logic-only, no GPU)
To just compile/test the backend-agnostic core (pool/cache/C-API) without Qt:
```
cmake -B build -S . -DRIFT_WITH_RHI=OFF -DRIFT_WITH_FFMPEG=OFF
cmake --build build
ctest --test-dir build            # smoke + parity check A
```
This needs only MSVC - no vcpkg/Qt - good for a quick sanity compile.
