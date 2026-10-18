"""How much of the app's text a character-orthography voice can actually say.

A checkpoint trained on a partial alphabet cannot voice every sentence, and the
app refuses to speak a sentence with a dropped letter rather than mispronounce
it. This measures that gap per language so the choice of voice is evidence-based.

Run:  python tool/voice_letter_coverage.py Dagbani dagbani_piper
"""
import json, re, sys, unicodedata

language = (sys.argv[1] if len(sys.argv) > 1 else 'Dagbani').lower()
pack = sys.argv[2] if len(sys.argv) > 2 else f'{language}_piper'
config = json.load(open(f'assets/tts/{pack}/model.onnx.json', encoding='utf8'))
frontend = config['character_frontend']
vocab, aliases = set(frontend['vocabulary']), frontend.get('aliases', {})

paths = (f'lib/core/i18n/{language}_strings.dart', 'lib/core/i18n/speech_bank.dart')
strings = []
for path in paths:
    try:
        handle = open(path, encoding='utf8')
    except FileNotFoundError:
        continue
    for line in handle:
        for pattern in (rf"{language}:\s*['\"](.+)['\"],?\s*$", rf"{language}:\s*['\"](.+)$"):
            match = re.search(pattern, line)
            if match:
                strings.append(match.group(1))
                break

unspeakable, spoken = {}, 0
for text in strings:
    expanded = ''.join(aliases.get(c, c) for c in text.lower())
    missing = {
        c for c in expanded
        if c not in vocab
        and not c.isspace()
        and not unicodedata.category(c)[0] in 'PSCK'
    }
    if missing:
        for c in missing:
            unspeakable[c] = unspeakable.get(c, 0) + 1
    else:
        spoken += 1

print(f'{language} lines checked: {len(strings)}  fully speakable: {spoken}')
print('letters the checkpoint lacks:',
      dict(sorted(unspeakable.items(), key=lambda kv: -kv[1])))
