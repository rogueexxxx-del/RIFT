# Contributing to RIFT

## Branches

- `main` is the stable, default branch. Release tags identify shipped versions.
- `dev` is the integration branch for upcoming changes.
- `feat/<topic>`, `fix/<topic>`, `docs/<topic>`, and `chore/<topic>` are short-lived branches. Open pull requests into `dev` unless the change is a release or a public documentation fix.
- `archive/v1.0.0` preserves the former `master` branch. Do not use it for new development.

Keep pull requests focused. Describe the user-facing change, the checks run, and any remaining limitations. Include screenshots for visible interface or effect changes.

## Source layout

| Directory | Contents |
| --- | --- |
| `src/` | C++20 engine, audio, media, rendering, and Qt integration |
| `include/rift/` | Public C API |
| `qml/` | Qt Quick desktop interface |
| `shaders_qrhi/` | GPU shaders, parameter layouts, and manifests |
| `assets/` | Bundled interface resources |
| `tests/` and `testdata/` | Automated checks and reference fixtures |
| `tools/` | Development utilities |
| `packaging/` | Windows packaging and release scripts |
| `docs/contracts/` | Serialized formats and shader interfaces |

## Build and test

Use Visual Studio 2022 with the C++ workload and CMake 3.24 or newer. The core can be built without Qt or FFmpeg:

```powershell
cmake -S . -B build -DRIFT_WITH_RHI=OFF -DRIFT_WITH_FFMPEG=OFF
cmake --build build --config Release
ctest --test-dir build -C Release --output-on-failure
```

The desktop application also needs the dependencies in `vcpkg.json`. Configure with the vcpkg toolchain and enable `RIFT_WITH_RHI`, `RIFT_WITH_FFMPEG`, and `RIFT_WITH_AUDIO`. Build the `rift_shell` target. See the [README](README.md#building-from-source) for the desktop build outline and [build setup notes](docs/BUILD_SETUP.md) for environment details.

Run the tests relevant to the change. Tests are standalone executables registered with CTest; GPU and media tests depend on the enabled build options and available hardware. Build `rift_shaders_all` after shader changes.

## Change conventions

- Match nearby C++, QML, and CMake style. Avoid unrelated formatting changes.
- Keep shader manifests and layouts in slot order. Update the corresponding contract when changing a serialized format or shader interface.
- Keep generated builds, exports, local media, assistant configuration, and diagnostic captures out of commits.
- Preserve dependency licenses and notices.
- Use concise scoped commit subjects, such as `fix(timeline): preserve clip selection`.
