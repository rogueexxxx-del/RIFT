"""Run isolated QML component tests with the project's installed Qt tools."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tests", nargs="*", default=["tst_workspace.qml", "tst_timeline.qml"])
    parser.add_argument("--style", default="Basic", help="Qt Quick Controls style to exercise")
    parser.add_argument("--qt-root", type=Path,
                        default=root / "build-release/vcpkg_installed/x64-windows")
    args = parser.parse_args()
    qt = args.qt_root.resolve()
    executable = qt / "tools/Qt6/bin/qmltestrunner.exe"
    if not executable.is_file():
        parser.error(f"Qt test runner not found: {executable}")
    env = os.environ.copy()
    env["PATH"] = str(qt / "bin") + os.pathsep + env.get("PATH", "")
    env["QT_PLUGIN_PATH"] = str(qt / "Qt6/plugins")
    env["QML_IMPORT_PATH"] = str(qt / "Qt6/qml")
    env["QT_QPA_PLATFORM"] = "minimal"
    env["QT_QUICK_BACKEND"] = "software"
    env["QT_QUICK_CONTROLS_STYLE"] = args.style
    result = 0
    with tempfile.TemporaryDirectory(prefix="rift-qml-", dir=os.environ.get("TMPDIR")) as directory:
        sandbox = Path(directory)
        (sandbox / "qml").mkdir()
        (sandbox / "tests").mkdir()
        (sandbox / "assets").mkdir()
        shutil.copyfile(root / "assets/effect_previews/ascii.png", sandbox / "assets/ascii.png")
        shutil.copytree(root / "assets/icons inspo", sandbox / "assets/icons inspo")
        for source in (root / "qml").iterdir():
            if source.suffix in (".qml", ".js"):
                shutil.copyfile(source, sandbox / "qml" / source.name)
        # Directory imports need explicit singleton metadata, unlike the built Rift module.
        (sandbox / "qml/qmldir").write_text("singleton Theme 1.0 Theme.qml\n", encoding="utf-8")
        for name in args.tests:
            source = root / "tests" / name
            if not source.is_file():
                parser.error(f"Test not found: {source}")
            target = sandbox / "tests" / source.name
            shutil.copyfile(source, target)
            log = sandbox / (source.stem + ".txt")
            command = [str(executable), "-input", str(target), "-o", str(log) + ",txt"]
            print("Running:", source.name, flush=True)
            try:
                run = subprocess.run(command, env=env, capture_output=True, text=True,
                                     errors="replace", timeout=60)
            except subprocess.TimeoutExpired as error:
                print(f"Test timed out: {source.name}: {error}", flush=True)
                result = 1
                continue
            print(run.stdout, end="", flush=True)
            print(run.stderr, end="", flush=True)
            if log.is_file():
                print(log.read_text(encoding="utf-8", errors="replace"), end="", flush=True)
            print(f"Exit code: {run.returncode}", flush=True)
            if run.returncode:
                result = 1
    return result


if __name__ == "__main__":
    raise SystemExit(main())
