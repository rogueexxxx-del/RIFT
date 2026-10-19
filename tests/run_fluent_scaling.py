from pathlib import Path
import argparse
import json
import math
import os
import re
import struct
import subprocess
import wave
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description='Verify compiled React/Live layouts at 100, 150 and 200 percent.')
parser.add_argument('--output-dir', type=Path, required=True)
parser.add_argument('--exe', type=Path, default=ROOT / 'build-release/Release/rift_shell.exe')
args = parser.parse_args()
args.output_dir.mkdir(parents=True, exist_ok=True)
OUT = Path(tempfile.mkdtemp(prefix='rift-fluent-', dir=args.output_dir))
print('Artifacts:', OUT, flush=True)
EXE = args.exe.resolve()
fixture = OUT / 'quiet-test.wav'
with wave.open(str(fixture), 'wb') as wav:
    wav.setparams((2, 2, 48000, 0, 'NONE', 'not compressed'))
    data = b''.join(struct.pack('<hh', *([round(1800 * math.sin(2 * math.pi * 443 * i / 48000))] * 2)) for i in range(48000))
    wav.writeframes(data * 12)

results = []
for scale in (1, 1.5, 2):
    folder = OUT / f'scale-{scale}'
    folder.mkdir(exist_ok=True)
    env = os.environ.copy()
    for key in ('QT_QUICK_BACKEND', 'QT_SCREEN_SCALE_FACTORS', 'QML_IMPORT_PATH', 'QT_PLUGIN_PATH', 'QT_QUICK_CONTROLS_STYLE'):
        env.pop(key, None)
    env.update(RIFT_UI_TESTQML=str(ROOT / 'tests/ui_fluent_probe.qml'), QT_SCALE_FACTOR=str(scale),
               QT_FORCE_STDERR_LOGGING='1', QT_QPA_PLATFORM='windows', QSG_RHI_BACKEND='d3d11')
    args = [str(EXE), '--probe-shaders', str(EXE.parent / 'shaders'),
        '--probe-assets', (ROOT / 'assets').as_uri() + '/', '--probe-audio', fixture.as_posix(),
        '--probe-output', folder.as_posix(), '--probe-layout', (folder / 'layout.ini').as_uri()]
    with (folder / 'run.log').open('w', encoding='utf-8') as log:
        p = subprocess.Popen(args, cwd=EXE.parent, env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            rc = p.wait(timeout=50)
        except subprocess.TimeoutExpired:
            p.kill(); p.wait(); raise
    text = (folder / 'run.log').read_text(errors='replace')
    errors = [line for line in text.splitlines() if re.search(r'TypeError|ReferenceError|Binding loop|Cannot assign', line)]
    metrics = [json.loads(line.split('FLUENT_METRICS ', 1)[1]) for line in text.splitlines() if 'FLUENT_METRICS ' in line]
    result = {'scale': scale, 'exit': rc, 'errors': errors, 'metrics': metrics}
    results.append(result)
    print(json.dumps(result), flush=True)
    if rc or errors or len(metrics) != 2 or 'FLUENT_COMPLETE' not in text:
        print(text[-3500:]); break
(OUT / 'results.json').write_text(json.dumps(results, indent=2))
assert len(results) == 3 and all(r['exit'] == 0 and not r['errors'] and len(r['metrics']) == 2 for r in results)
for result in results:
    react = result['metrics'][0]
    assert len(react['tracks']) == 2, result
    assert all(clip['fits'] for clip in react['tracks']), result
    assert all(m['previewHeight'] >= 96 for m in result['metrics']), result
print('PASS: React and Live at 100/150/200%; both fixture tracks visible vertically')
