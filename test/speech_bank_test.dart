/// On-device speech banks (Dagbani, Hausa, Twi) — asset coverage, clip-map
/// correctness and draft-drift guards.
///
/// The promise the app makes to a Dagbani-, Hausa- or Twi-speaking family is
/// that the audio button *plays* their language, offline. These tests pin
/// that promise: every clip id the mapping layer or the guide can emit must
/// exist as a bundled WAV in every bank that claims the language, the
/// composed-message helper must order clips the way the screen reads them,
/// and the Dagbani column must never drift from `dagbani_strings.dart`.
/// If a draft changes or a clip is renamed without regenerating the bank,
/// this file fails — the drift never reaches a caregiver as silence.
library;

import 'package:carebridge_ai/core/audio/audio_guide.dart';
import 'package:carebridge_ai/core/i18n/dagbani_strings.dart';
import 'package:carebridge_ai/core/i18n/speech_bank.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The folder a clip id belongs to. A language-suffixed standalone
  /// (`setup_preview_Hausa`) names its own file inside its language's
  /// folder; every shared id must exist in ALL three banks.
  String? folderForClip(String id) {
    final suffix = id.split('_').last;
    if (SpeechBank.bankLanguages.containsKey(suffix)) {
      return SpeechBank.bankLanguages[suffix];
    }
    return null;
  }

  Future<int> clipBytes(String folder, String id) async =>
      (await rootBundle.load('assets/audio/$folder/$id.wav')).lengthInBytes;

  test(
    'every clip in the SpeechBank map is bundled, in the right folder(s)',
    () async {
      for (final clip in SpeechBank.allScripts) {
        final folder = folderForClip(clip.id);
        if (folder == null) {
          for (final bank in SpeechBank.bankLanguages.entries) {
            final bytes = await clipBytes(bank.value, clip.id);
            expect(
              bytes,
              greaterThan(1000),
              reason:
                  '${clip.id}.wav in ${bank.value} exists but is not real '
                  'audio',
            );
          }
        } else {
          final bytes = await clipBytes(folder, clip.id);
          expect(
            bytes,
            greaterThan(1000),
            reason: '${clip.id}.wav exists but is not real audio',
          );
        }
      }
    },
  );

  test('every audio topic has a bundled clip in every bank', () async {
    for (final topic in AudioTopic.values) {
      for (final folder in SpeechBank.bankLanguages.values) {
        await clipBytes(folder, topic.id);
      }
    }
  });

  test('every triage-question key has a clip in every bank', () async {
    // The runtime ids are `q_<group>.<sign>` (AudioGuide.playQuestion
    // prefixes the group) — exactly the keys registered here, with the
    // first dot of the key becoming the id separator.
    for (final s in DagbaniStrings.all) {
      if (!s.key.startsWith('q.')) continue;
      final id = s.key.replaceFirst('.', '_');
      for (final folder in SpeechBank.bankLanguages.values) {
        await clipBytes(folder, id);
      }
    }
  });

  test('the Dagbani column mirrors dagbani_strings.dart verbatim', () {
    // SpeechBank carries the wording DagbaniStrings owns, so the script
    // sheet and the speaker always agree. If this fails, the draft was
    // edited in one place only — fix the wording there and regenerate.
    for (final s in DagbaniStrings.all) {
      if (!s.key.startsWith('q.')) continue;
      final clip = SpeechBank.byId(s.key.replaceFirst('.', '_'));
      expect(clip, isNotNull, reason: '${s.key} has no clip in SpeechBank');
      expect(
        clip!.dagbani,
        s.dagbani,
        reason:
            '${clip.id}: speech_bank.dart Dagbani text drifted from '
            'dagbani_strings.dart',
      );
    }
    expect(
      SpeechBank.byId('setup_preview_Dagbani')!.dagbani,
      DagbaniStrings.verdictUrgent.dagbani,
    );
  });

  test('every TriageLevel has a family message clip in every language', () {
    final ids = <String>{};
    for (final level in TriageLevel.values) {
      final clip = SpeechBank.levelClip(level.name);
      expect(
        clip,
        isNotNull,
        reason:
            'TriageLevel.${level.name} has no family message — add one to '
            'SpeechBank or the result screen goes quiet.',
      );
      ids.add(clip!.id);
      for (final language in SpeechBank.bankLanguages.keys) {
        expect(
          clip.textFor(language),
          isNotNull,
          reason: '${clip.id} has no $language words',
        );
      }
    }
    expect(ids.length, TriageLevel.values.length, reason: 'clips collide');
  });

  test('every caregiver verdict name has a clip in every language', () {
    for (final name in const ['urgent', 'caution', 'fine']) {
      final clip = SpeechBank.caregiverVerdictClip(name);
      expect(clip, isNotNull, reason: 'no clip for verdict "$name"');
      for (final language in SpeechBank.bankLanguages.keys) {
        expect(
          clip!.textFor(language),
          isNotNull,
          reason: '${clip.id} has no $language words',
        );
      }
    }
  });

  test('nurse-words composition orders clips like the sheet reads', () {
    final clips = SpeechBank.clipsForNurseWords(
      yesKeys: const ['newborn.feed', 'child.fits'],
      unsureKeys: const ['mother.bleed'],
    );
    expect(clips, const [
      'nurse_intro',
      'q_newborn.feed',
      'q_child.fits',
      'nurse_unsure',
      'q_mother.bleed',
      'nurse_close',
    ]);

    // No unsure answers: the preamble must be skipped entirely.
    final clean = SpeechBank.clipsForNurseWords(
      yesKeys: const ['child.drink'],
      unsureKeys: const [],
    );
    expect(clean, const ['nurse_intro', 'q_child.drink', 'nurse_close']);
  });

  test('scriptFor resolves composed clips in all three languages', () {
    final clips = SpeechBank.clipsForNurseWords(
      yesKeys: const ['child.fits', 'newborn.feed'],
      unsureKeys: const [],
    );
    expect(
      SpeechBank.scriptFor(language: 'Dagbani', ids: clips),
      contains('Bini maa ti zuɣa'), // child fits statement
    );
    expect(
      SpeechBank.scriptFor(language: 'Hausa', ids: clips),
      contains('Yaron na tautsiya'),
    );
    expect(
      SpeechBank.scriptFor(language: 'Twi', ids: clips),
      contains('Sɛsɛa asi no'),
    );

    // An unknown id must return null — the sheet falls back to the
    // caller's script instead of showing a half-joined sentence. A
    // language with no bank returns null too (never throws).
    expect(
      SpeechBank.scriptFor(language: 'Dagbani', ids: const ['no_such_clip']),
      isNull,
    );
    expect(SpeechBank.scriptFor(language: 'Mampruli', ids: clips), isNull);
  });

  test('standalone moments stay in sync with their screens', () {
    // The voice-test phrase must be exactly what the voice-test screen
    // shows for Hausa, so the demo proves the bank speaks real Hausa.
    expect(
      SpeechBank.byId('voice_test_Hausa')!.hausa,
      'Idan yaranku ba ta iya sha ko nono, je asibitin yanzu.',
    );
    // Languages without a bank have no folder and no id.
    expect(SpeechBank.folderFor('English'), isNull);
    expect(SpeechBank.folderFor('Mampruli'), isNull);
    expect(SpeechBank.byId('no_such_clip'), isNull);
  });

  test('every clip carries words in all three bank languages', () {
    for (final clip in SpeechBank.allScripts) {
      expect(clip.english, isNotEmpty, reason: clip.id);
      expect(clip.dagbani, isNotEmpty, reason: clip.id);
      expect(clip.hausa, isNotEmpty, reason: clip.id);
      expect(clip.twi, isNotEmpty, reason: clip.id);
    }
  });
}
