"""Mechanical adoption of inventoried guidance constructors only."""
from pathlib import Path
import re
root = Path(__file__).resolve().parents[1]
p = root / 'lib/presentation/shared/recommendation_kit.dart'
s = p.read_text(encoding='utf-8')
if "import 'speakable_text.dart';" not in s:
    s = s.replace("import 'audio_button.dart';", "import 'audio_button.dart';\nimport 'speakable_text.dart';")
# Each pattern identifies an existing guidance argument, never a button label.
fields = [
    'subtitle!', 'widget.subtitle!', 'text', 'note', 'action.instruction',
    'action.rationale!', 'plan.headline', 'plan.cohortLine!', 'plan.seasonNote',
    'plan.therapeuticPlan!.counsellingHeadline', 'plan.dayPlanNote!', 'rule',
    "slots[i].foods.join(' + ')", 'slots[i].note!', 'food.householdMeasure',
    'food.reason', 'food.preparation', 'food.caution!', 'supplement.label',
    'supplement.counsellingNote', 'supplement.contraindications!',
    'supplement.localSources!', 'line', 'plan.summary', 'item.detail',
    'protocol.headline', 'protocol.urgencyNote', 'step.action', 'style.why',
    'summary', 'action.counsellingNote', 'message',
]
clinical = {'action.instruction', 'action.rationale!',
    'plan.therapeuticPlan!.counsellingHeadline', 'supplement.label',
    'supplement.counsellingNote', 'supplement.contraindications!', 'line',
    'item.detail', 'protocol.headline', 'protocol.urgencyNote', 'step.action'}
count = 0
for field in fields:
    pattern = r'\bText\((\s*' + re.escape(field) + r'\s*)(?=[,)])'
    def replace(m):
        return 'SpeakableText(' + m[1] + (', policy: SpeechContentPolicy.clinical' if field in clinical else '')
    s, n = re.subn(pattern, replace, s)
    count += n
    if n: print(field, n)
# Explicit guidance literals and conditional food/follow-up display arguments.
starts = [
    "'Feeding target:", "'BRING BACK IMMEDIATELY IF:", r"'\u2022 $sign",
    "'Nutrition review in", 'food.localName != null', "'DOSE:", "'WHEN:",
    "'WHY:", "'CAUTION:", "'Why it matters:", "'IN ${", "'Next due:",
    "'GO TO THE CLINIC IF YOU SEE:", r"'\u2022 $d", "'Saved clinic advice from",
    "'Clinic decision", 'savedAt == null',
]
for start in starts:
    s, n = re.subn(r'\bText\((\s*' + re.escape(start) + ')', r'SpeakableText(\1', s)
    count += n
    if n: print(start, n)
s, n = re.subn(r'\bText\.rich\(', 'SpeakableText.rich(', s)
count += n
# All value cells within the prescription renderer are explicitly protected.
a = s.index('class _PrescriptionCard')
b = s.index('class _HydrationCard', a)
section = s[a:b]
section = re.sub(r'\bText\((\s*value\s*),', r'SpeakableText(\1, policy: SpeechContentPolicy.clinical,', section)
s = s[:a] + section + s[b:]
# Clinical instructions that are interpolated strings retain their full source.
a = s.index('class _ProtocolCard')
b = s.index('class FamilyCarePlanCard', a)
section = s[a:b]
section = re.sub(r"\bText\((\s*'[^'\n]*(?:step\.|protocol\.)[^'\n]*')\s*,", r'SpeakableText(\1, policy: SpeechContentPolicy.clinical,', section)
s = s[:a] + section + s[b:]
p.write_text(s, encoding='utf-8', newline='\n')
print('Adopted constructors:', count)
