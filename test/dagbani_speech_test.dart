/// Dagbani voice bank — asset coverage and clip-map correctness.
///
/// The promise the app makes to a Dagbani-speaking family is that the audio
/// button *plays*, in Dagbani, offline. These tests pin that promise:
/// every clip id the mapping layer or the guide can emit must exist as a
/// bundled WAV, and the composed-message helpers must order clips the way
/// the screen reads them. If a draft changes or a clip is renamed without
/// regenerating the bank, this file fails — the drift never reaches a
/// caregiver as silence.
library;

import 'package:carebridge_ai/core/audio/audio_guide.dart';
import 'package:carebridge_ai/core/i18n/dagbani_speech.dart';
import 'package:carebridge_ai/core/i18n/dagbani_strings.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _bank = 'assets/audio/dagbani_mms';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ByteData> loadClip(String id) => rootBundle.load('$_bank/$id.wav');

  test('every clip in the DagbaniSpeech map is bundled', () async {
    for (final clip in DagbaniSpeech.allClips) {
      final bytes = await loadClip(clip.id);
      expect(
        bytes.lengthInBytes,
        greaterThan(1000),
        reason: '${clip.id}.wav exists but is not real audio',
      );
    }
  });

  test('every audio topic has a bundled clip', () async {
    for (final topic in AudioTopic.values) {
      await loadClip(topic.id);
    }
  });

  test('every triage-question key has a bundled clip', () async {
    // The runtime ids are `q_<group>.<sign>` (AudioGuide.playQuestion
    // prefixes the group) — exactly the keys registered here, with the
    // first dot of the key becoming the id separator.
    for (final s in DagbaniStrings.all) {
      if (!s.key.startsWith('q.')) continue;
      final id = s.key.replaceFirst('.', '_');
      await loadClip(id);
    }
  });

  test('every TriageLevel has a family message clip', () {
    final ids = <String>{};
    for (final level in TriageLevel.values) {
      final clip = DagbaniSpeech.levelClip(level.name);
      expect(
        clip,
        isNotNull,
        reason:
            'TriageLevel.${level.name} has no Dagbani family message '
            '— add one to DagbaniSpeech or the result screen goes quiet.',
      );
      ids.add(clip!.id);
    }
    expect(ids.length, TriageLevel.values.length, reason: 'clips collide');
  });

  test('every caregiver verdict name has a clip', () {
    for (final name in const ['urgent', 'caution', 'fine']) {
      expect(DagbaniSpeech.caregiverVerdictClip(name), isNotNull);
    }
  });

  test('nurse-words composition orders clips like the sheet reads', () {
    final clips = DagbaniSpeech.clipsForNurseWords(
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
    final clean = DagbaniSpeech.clipsForNurseWords(
      yesKeys: const ['child.drink'],
      unsureKeys: const [],
    );
    expect(clean, const ['nurse_intro', 'q_child.drink', 'nurse_close']);
  });

  test('scriptForClips resolves every clip it is handed', () {
    final clips = DagbaniSpeech.clipsForNurseWords(
      yesKeys: const ['child.fits', 'newborn.feed'],
      unsureKeys: const [],
    );
    final script = DagbaniSpeech.scriptForClips(clips);
    expect(script, isNotNull);
    expect(script, contains('Bini maa ti zuɣa')); // child fits statement
    // An unknown id must return null — the sheet falls back to the
    // caller's script instead of showing a half-joined sentence.
    expect(DagbaniSpeech.scriptForClips(const ['no_such_clip']), isNull);
  });
}
