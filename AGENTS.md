# Repository Guidelines

## Project Structure & Module Organization

`src/` contains the C++20 engine, audio, media, rendering, and Qt integration. Public C API headers live in `include/rift/`; the desktop interface lives in `qml/`. GPU effects are kept in `shaders_qrhi/`, typically as matching `<effect>.frag`, `<effect>.layout.json`, and `<effect>.manifest.json` files. Put C++ checks in `tests/` and reference data in `testdata/`. `assets/` holds bundled UI resources; `tools/` and `packaging/` hold developer and release scripts. Use `docs/contracts/` when changing a serialized format or shader interface.

## Build, Test, and Development Commands

Use Visual Studio 2022, CMake 3.24+, and the dependencies described in `README.md` and `vcpkg.json`. Run commands from the repository root:

```powershell
cmake -S . -B build -DRIFT_WITH_RHI=OFF -DRIFT_WITH_FFMPEG=OFF
cmake --build build --config Release
ctest --test-dir build -C Release --output-on-failure
```

This builds and tests the core without Qt or FFmpeg. For the desktop app, configure with the vcpkg toolchain and `-DRIFT_WITH_RHI=ON -DRIFT_WITH_FFMPEG=ON -DRIFT_WITH_AUDIO=ON`, then build the `rift_shell` target. Run `build/Release/rift_shell.exe` for a multi-config Visual Studio build. After shader changes, build `rift_shaders_all` to compile every effect.

## Coding Style & Naming Conventions

Match the surrounding file: C++ and QML generally use four-space indentation; CMake uses two. Keep C++ implementation in `src/` with lowercase snake_case filenames, QML components in PascalCase filenames, and shader IDs in lowercase snake_case. Follow existing `rift::` types and Qt/QML property conventions. No repository-wide formatter or linter configuration is committed, so avoid unrelated reformatting.

## Testing Guidelines

Tests are standalone C++ executables registered with CTest in `CMakeLists.txt`; there is no separate test framework or stated coverage threshold. Name new C++ test files `*_test.cpp`, register them with `add_test`, and run the relevant CTest suite. GPU, media, and export tests depend on enabled build options and hardware; `rift_preview_test` is interactive and is not a CTest case. Keep shader manifests and layouts in slot order; the `manifest` test checks this contract.

## Commits & Pull Requests

Recent commits use concise `feat(scope):`, `fix(scope):`, or `docs:` subjects; older release commits use version-led subjects. Use the scoped form for ordinary changes. In pull requests, explain the user-facing change, list the build and tests run, link a related issue when one exists, and include screenshots for visible QML or shader changes. Keep generated builds, exports, and local media out of the diff.

## Reading Scope (save tokens)

- Work inside the one directory the task is about. Do not scan the whole repo.
- Never read or list `build/`, `vcpkg_installed/`, exports, or media files in `testdata/` unless the task is about them.
- For a shader task, read only that effect's `.frag`, `.layout.json`, and `.manifest.json`, plus the relevant contract in `docs/contracts/`.
- For a QML task, read only the component being changed and the ones it directly imports.
- Prefer building and running one target or one CTest suite over the full build.
- If it is unclear which files matter, ask first.

## Key Files (read first)

- [path]: [what it does]
- [path]: [what it does]
- [path]: [what it does]

## Ask Before

- Changing any serialized format or shader interface. Update `docs/contracts/` in the same change.
- Adding a dependency to `vcpkg.json` or `CMakeLists.txt`.
- Renaming or moving files in `src/`, `qml/`, or `shaders_qrhi/`.
- Changing public headers in `include/rift/`.

## UI Rules (QML and shaders)

- Sharp corners. Use `radius: 0` or no radius. No rounded shapes.
- No colored shadows or glows.
- Keep the dark, editorial, industrial minimal look. Match existing components before adding new styles.
- No em dashes in any UI text, docs, or comments. Plain, direct wording.
- These rules can change. If a task needs something that breaks a rule, or the rules seem to conflict with what I ask, stop and ask me before going ahead.
- If a task is a visual change and the rules do not cover it, ask me instead of guessing.
- Do not edit this section yourself. I update it.

## Skills

Use these two skills in every session:

- caveman: use for all chat replies, to keep them short. Chat only. Never apply it to code, UI text, docs, or commit messages, which stay in normal plain writing.
- ponytail: use for all code changes. Write the shortest solution that works. Do not cut security, input validation, or error handling. Activate both at the start of each session. If a task seems to fit a skill that is not listed here, tell me which one and ask before using it.

## Decisions Already Made

- [decision and a few words on why]

## Do Not Touch

- [files or folders]
