"""Build a same-origin PWA shell separately from optional neural language packs."""
import argparse
import hashlib
import re
import shutil
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def stage_packs(output, translation_root):
    """Publish optional artifacts without adding them to Flutter's asset bundle."""
    for language in ['twi', 'hausa']:
        sources = [
            (ROOT / 'assets' / 'tts' / f'{language}_piper', f'assets/tts/{language}_piper', 'piper-v1'),
            (translation_root / f'translation_{language}', f'assets/models/translation_{language}', 'marian-v1'),
        ]
        for source, base, contract in sources:
            manifest = json.loads((source / 'model_manifest.json').read_text(encoding='utf-8'))
            if manifest.get('schema') != 1 or manifest.get('contract') != contract:
                raise ValueError('Unsupported pack contract')
            if contract == 'marian-v1':
                fixtures = json.loads((source / 'generation_fixtures.json').read_text(encoding='utf-8'))
                if not fixtures or any(not row.get('translation', '').strip() for row in fixtures):
                    raise ValueError('Empty generation reference')
                report = source / 'quantization_report.json'
                if report.exists() and not json.loads(report.read_text()).get('all_reference_ids_match'):
                    raise ValueError('Rejected candidate cannot be staged')
            destination = output / 'assets' / base
            destination.mkdir(parents=True, exist_ok=True)
            names = set()
            for record in manifest['files']:
                name = record['name']
                if not re.fullmatch(r'[a-zA-Z0-9_.-]+', name) or name in {'.', '..'} or name in names:
                    raise ValueError('Invalid artifact name')
                names.add(name)
                path = source / name
                with path.open('rb') as stream:
                    prefix = stream.read(64)
                    stream.seek(0)
                    digest = hashlib.file_digest(stream, 'sha256').hexdigest()
                if (path.stat().st_size != record['bytes'] or digest != record['sha256'] or
                        prefix.startswith(b'version https://git-lfs')):
                    raise ValueError(f'Pack integrity failed: {base}/{name}')
                shutil.copyfile(path, destination / name)
            shutil.copyfile(source / 'model_manifest.json', destination / 'model_manifest.json')
            print(f'Optional {base}: {sum(f["bytes"] for f in manifest["files"]):,} bytes (not runtime certification)')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--packs-only', action='store_true')
    parser.add_argument('--probe', action='store_true', help='Build a separate browser acceptance harness')
    parser.add_argument('--translation-root', type=Path, default=ROOT / 'build' / 'marian_reference')
    args = parser.parse_args()
    output = ROOT / 'build' / ('voice_probe' if args.probe else 'web')
    if not args.packs_only:
        command = 'flutter build web --release --pwa-strategy=none --no-web-resources-cdn'
        if args.probe:
            command += ' --target tool/offline_voice_probe.dart --output build/voice_probe'
        subprocess.run(command, cwd=ROOT, shell=True, check=True)
    stage_packs(output, args.translation_root)
    if args.packs_only:
        return
    fonts = json.loads((output / 'assets' / 'FontManifest.json').read_text(encoding='utf-8'))
    if not any(font.get('family') == 'Roboto' for font in fonts):
        raise RuntimeError('Missing bundled CanvasKit default font; offline startup would fetch Roboto')
    bootstrap = (output / 'flutter_bootstrap.js').read_text(encoding='utf-8')
    if "fontFallbackBaseUrl: 'font_fallbacks/'" not in bootstrap:
        raise RuntimeError('Renderer font fallback must remain same-origin')
    files = []
    for path in sorted(output.rglob('*')):
        if not path.is_file():
            continue
        name = path.relative_to(output).as_posix()
        if name in {'app_sw.js', 'offline_shell.json', 'flutter_service_worker.js'}:
            continue
        if name.startswith(('assets/assets/tts/', 'assets/assets/models/translation_')) or name.endswith('.map'):
            continue
        data = path.read_bytes()
        files.append({'name': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
    for folder in ['dagbani_mms', 'hausa_mms', 'twi_mms']:
        expected = list((ROOT / 'assets' / 'audio' / folder).glob('*.wav'))
        actual = list((output / 'assets' / 'assets' / 'audio' / folder).glob('*.wav'))
        if not expected or len(expected) != len(actual):
            raise RuntimeError(f'Missing rebuilt speech recordings: {folder}')
    revision = hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()
    (output / 'offline_shell.json').write_text(json.dumps({'schema': 1, 'revision': revision, 'files': files}), encoding='utf-8')
    worker = (ROOT / 'web' / 'app_sw.js').read_text(encoding='utf-8')
    (output / 'app_sw.js').write_text(worker.replace('__SHELL_REVISION__', revision), encoding='utf-8')
    print(f'Offline shell: {len(files)} artifacts, {sum(file["bytes"] for file in files):,} bytes; models excluded')


if __name__ == '__main__':
    main()
