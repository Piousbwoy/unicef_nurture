/// Caregiver shell language warm-up.
///
/// The FHW shell pre-loads the translation and Piper models for the chosen
/// language so the first tap of a play button does not stall for minutes.
/// A family in the caregiver shell picks their language the same way
/// (narrationLanguageProvider), so they must get the same warm-up — and the
/// same guards: Hausa/Twi get translation plus voice, Dagbani only a voice,
/// serialized loads, honest runtime caching, cancellation on language change or
/// sign-out, and never any narration preference writes or model disposal.
library;

import 'dart:async';

import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/core/ml/neural_translation_service.dart';
import 'package:carebridge_ai/core/ml/piper_contract.dart';
import 'package:carebridge_ai/core/ml/piper_tts_runner.dart';
import 'package:carebridge_ai/core/ml/piper_tts_service.dart';
import 'package:carebridge_ai/core/ml/translation_runner.dart';
import 'package:carebridge_ai/domain/entities/caregiver.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/domain/services/caregiver_today_planner.dart';
import 'package:carebridge_ai/presentation/caregiver/caregiver_home.dart';
import 'package:carebridge_ai/presentation/caregiver/caregiver_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _scope = CaregiverScope(userId: 'caregiver', householdId: 'household');
const _person = Person(
  id: 'child',
  householdId: 'household',
  fullName: 'Abdul-Rahman Suleimana Alhassan',
  clientType: ClientType.childUnderFive,
);

AppUser _family({String language = 'English'}) => AppUser(
  id: 'caregiver',
  fullName: 'Mariama Alhassan',
  phone: '',
  role: UserRole.caregiver,
  region: 'Northern Region',
  district: 'Tamale',
  community: 'Tamale',
  preferredLanguage: language,
);

final _accountProvider = StateProvider<AppUser?>((_) => _family());

Future<ProviderContainer> _pumpShell(
  WidgetTester tester, {
  AppUser? user,
  _WarmupHarness? warmup,
}) async {
  final models = warmup ?? _WarmupHarness();
  tester.view.physicalSize = const Size(320, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        _accountProvider.overrideWith((_) => user ?? _family()),
        currentUserProvider.overrideWith((ref) => ref.watch(_accountProvider)),
        fhwLanguageServicesProvider.overrideWithValue((
          neural: models.neural,
          piper: models.piper,
        )),
        fhwWarmupRuntimeReadyProvider.overrideWithValue(models.runtimeReady),
        narrationPreferenceReaderProvider.overrideWith(
          (_) =>
              () async => false,
        ),
        narrationPreferenceWriterProvider.overrideWith(
          (_) => (_) async {
            fail('Warm-up must not write narration preferences');
          },
        ),
        caregiverScopeProvider.overrideWithValue(_scope),
        householdProvider.overrideWith((ref, id) async => null),
        householdMembersProvider.overrideWith((ref, id) async => [_person]),
        caregiverSettingsProvider.overrideWith((ref, scope) async {
          return CaregiverSettings(
            scope: scope,
            selectedPersonId: null,
            updatedAt: DateTime(2026, 9, 24),
          );
        }),
        caregiverClockProvider.overrideWithValue(
          () => DateTime(2026, 9, 24, 15),
        ),
        caregiverTodayProvider.overrideWith(
          (ref, scope) async =>
              CaregiverDay(dateKey: '2026-09-24', attention: [], routine: []),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: false),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: const Scaffold(body: CaregiverHome()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(CaregiverHome)));
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  for (final language in ['Hausa', 'Twi']) {
    testWidgets('a $language family warms translation then Piper once', (
      tester,
    ) async {
      final models = _WarmupHarness();
      await _pumpShell(
        tester,
        user: _family(language: language),
        warmup: models,
      );

      expect(models.neural.isLoaded(language), isTrue);
      expect(models.piper.supportsLanguage(language), isTrue);
      expect(models.log.loads, ['translation:$language', 'piper:$language']);
      expect(models.log.maxActive, 1);
      expect(models.log.nonLoadingCalls, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('language switches warm the new preference and never translate', (
    tester,
  ) async {
    final models = _WarmupHarness();
    final container = await _pumpShell(tester, warmup: models);
    expect(models.log.loads, isEmpty);

    for (final language in ['Hausa', 'Twi']) {
      container.read(_accountProvider.notifier).state = _family(
        language: language,
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(models.neural.isLoaded(language), isTrue);
      expect(models.piper.supportsLanguage(language), isTrue);
    }
    expect(models.log.loads, [
      'translation:Hausa',
      'piper:Hausa',
      'translation:Twi',
      'piper:Twi',
    ]);
    expect(models.log.nonLoadingCalls, isEmpty);
  });

  testWidgets('a switch skips stale work and serializes the new language', (
    tester,
  ) async {
    final models = _WarmupHarness();
    final gate = models.translation.gate = Completer<void>();
    final container = await _pumpShell(
      tester,
      user: _family(language: 'Hausa'),
      warmup: models,
    );
    expect(models.log.loads, ['translation:Hausa']);
    container.read(_accountProvider.notifier).state = _family(language: 'Twi');
    await tester.pumpAndSettle();
    expect(models.log.loads, ['translation:Hausa']);
    gate.complete();
    await tester.pumpAndSettle();

    expect(models.log.loads, [
      'translation:Hausa',
      'translation:Twi',
      'piper:Twi',
    ]);
    expect(models.log.maxActive, 1);
    expect(models.piper.supportsLanguage('Hausa'), isFalse);
    expect(models.piper.supportsLanguage('Twi'), isTrue);
  });

  testWidgets('unsupported families and non-caregiver accounts never warm', (
    tester,
  ) async {
    final models = _WarmupHarness();
    final container = await _pumpShell(tester, warmup: models);
    for (final language in ['English', 'French', '']) {
      container.read(_accountProvider.notifier).state = _family(
        language: language,
      );
      await tester.pumpAndSettle();
    }
    // Dagbani ships a voice pack and no translation pack, so warm-up may load
    // exactly one of the two.
    container.read(_accountProvider.notifier).state = _family(
      language: 'Dagbani',
    );
    await tester.pumpAndSettle();
    expect(models.log.loads, ['piper:Dagbani']);
    expect(models.neural.isLoaded('Dagbani'), isFalse);
    container.read(_accountProvider.notifier).state = AppUser.fromMap({
      ..._family(language: 'Twi').toMap(),
      'role': 'frontlineHealthWorker',
    });
    await tester.pumpAndSettle();
    container.read(_accountProvider.notifier).state = null;
    await tester.pumpAndSettle();
    expect(models.log.loads, ['piper:Dagbani']);
    expect(models.log.nonLoadingCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an uncached runtime declines warm-up without errors', (
    tester,
  ) async {
    final models = _WarmupHarness()
      ..runtimeCached = false
      ..runtimeError = true;
    await _pumpShell(
      tester,
      user: _family(language: 'Hausa'),
      warmup: models,
    );
    expect(models.log.loads, isEmpty);
    expect(models.neural.isLoaded('Hausa'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sign-out cancels pending warm-up without disposing models', (
    tester,
  ) async {
    final models = _WarmupHarness();
    final gate = models.translation.gate = Completer<void>();
    final container = await _pumpShell(
      tester,
      user: _family(language: 'Twi'),
      warmup: models,
    );
    expect(models.log.loads, ['translation:Twi']);
    container.read(_accountProvider.notifier).state = null;
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(models.log.loads, ['translation:Twi']);
    expect(models.log.nonLoadingCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed packs stay quiet and a later language still warms', (
    tester,
  ) async {
    final models = _WarmupHarness()
      ..translation.failures.add('Hausa')
      ..voice.failures.add('Hausa');
    final container = await _pumpShell(
      tester,
      user: _family(language: 'Hausa'),
      warmup: models,
    );
    expect(models.log.loads, ['translation:Hausa', 'piper:Hausa']);
    expect(models.neural.isLoaded('Hausa'), isFalse);
    expect(models.piper.supportsLanguage('Hausa'), isFalse);
    expect(tester.takeException(), isNull);
    container.read(_accountProvider.notifier).state = _family(language: 'Twi');
    await tester.pump();
    await tester.pumpAndSettle();
    expect(models.neural.isLoaded('Twi'), isTrue);
    expect(models.piper.supportsLanguage('Twi'), isTrue);
    expect(models.log.nonLoadingCalls, isEmpty);
  });
}

// Only the slow/platform runner boundary is replaced. Service loading,
// deduplication, failure handling and readiness all remain production code.
class _WarmupHarness {
  bool runtimeCached = true;
  bool runtimeError = false;
  Completer<void>? runtimeGate;

  Future<bool> runtimeReady() async {
    await runtimeGate?.future;
    if (runtimeError) throw StateError('Offline runtime check unavailable');
    return runtimeCached;
  }

  final log = _LoadLog();
  late final translation = _TranslationRunner(log);
  late final voice = _VoiceRunner(log);
  late final neural = NeuralTranslationService.debugCreate(runner: translation);
  late final piper = PiperTtsService.debugCreate(runner: voice);
}

class _LoadLog {
  final loads = <String>[];
  final nonLoadingCalls = <String>[];
  int active = 0;
  int maxActive = 0;
}

class _ControlledModel {
  _ControlledModel(this.log, this.kind);
  final _LoadLog log;
  final String kind;
  String? loaded;
  Completer<void>? gate;
  final failures = <String>{};
  bool unavailable = false;
  bool throwAvailability = false;

  bool get available {
    if (throwAvailability) throw StateError('Runtime unavailable');
    return !unavailable;
  }

  bool hasModel(String language) => loaded == language;

  Future<void> load(String language) async {
    log.loads.add('$kind:$language');
    log.active++;
    if (log.active > log.maxActive) log.maxActive = log.active;
    try {
      await gate?.future;
      if (failures.contains(language)) throw StateError('Missing/corrupt pack');
      loaded = language;
    } finally {
      log.active--;
    }
  }

  Future<void> dispose(String language) async {
    log.nonLoadingCalls.add('dispose:$kind:$language');
    if (loaded == language) loaded = null;
  }
}

class _TranslationRunner extends _ControlledModel implements TranslationRunner {
  _TranslationRunner(_LoadLog log) : super(log, 'translation');

  @override
  Future<void> init({
    required String language,
    required String assetBasePath,
  }) => load(language);

  @override
  Future<String?> translate(
    String english, {
    required String language,
    String? langToken,
  }) async {
    log.nonLoadingCalls.add('translate:$language');
    return null;
  }
}

class _VoiceRunner extends _ControlledModel implements PiperTtsRunner {
  _VoiceRunner(_LoadLog log) : super(log, 'piper');

  @override
  Future<void> init({
    required String language,
    required String modelAssetPath,
    required int speakerId,
  }) => load(language);

  @override
  bool get isSpeaking => false;

  @override
  void setActiveLanguage(String language) {
    log.nonLoadingCalls.add('activate:$language');
  }

  @override
  Future<void> speak(
    String text, {
    bool waitForCompletion = true,
    void Function()? onStarted,
    SpeechProsody prosody = SpeechProsody.standard,
  }) async {
    log.nonLoadingCalls.add('speak');
  }

  @override
  Future<void> speakNonBlocking(
    String text, {
    SpeechProsody prosody = SpeechProsody.standard,
  }) async {
    log.nonLoadingCalls.add('speakNonBlocking');
  }

  @override
  Future<void> stop() async {
    log.nonLoadingCalls.add('stop');
  }
}
