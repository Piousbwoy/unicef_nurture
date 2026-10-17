/// The FHW shell chrome — the deep-blue clinic header that sits above every
/// tab.
///
/// The header used to place a `Flexible` directly inside a `Wrap`. A `Wrap`
/// hands its children unbounded width, so the parent-data write fails during
/// build and Flutter drops the whole subtree: on the web release build the
/// header *and* both tab bodies collapsed into an empty grey panel, which no
/// tab-body-only test could see. These pump the real shell so the crash is a
/// test failure, and pin the truncation the `Flexible` was there to achieve.
library;

import 'dart:async';

import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/core/ml/neural_translation_service.dart';
import 'package:carebridge_ai/core/ml/piper_contract.dart';
import 'package:carebridge_ai/core/ml/piper_tts_runner.dart';
import 'package:carebridge_ai/core/ml/piper_tts_service.dart';
import 'package:carebridge_ai/core/ml/translation_runner.dart';
import 'package:carebridge_ai/data/local/outbox_dao.dart';
import 'package:carebridge_ai/data/repositories/insight_repository.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/fhw/fhw_home.dart';
import 'package:carebridge_ai/presentation/fhw/home_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// A CHPS zone long enough to need the ellipsis, so the width ceiling is
/// actually exercised rather than silently absent.
const _longZone = 'Nakpayili & Kpalbusi CHPS Zone, Gushegu District';

final _user = AppUser(
  id: 'u-fhw-header',
  fullName: 'Amina Fuseini',
  phone: '0244000000',
  role: UserRole.frontlineHealthWorker,
  region: 'Northern Region',
  district: 'Gushegu',
  community: 'Tamale Central',
  chpsZone: _longZone,
);

const _household = Household(
  id: 'h-header',
  name: 'Achana household',
  region: 'Northern Region',
  district: 'Gushegu',
  community: 'Tamale Central',
  createdBy: 'u-fhw-header',
  headName: 'Achana Yakubu',
  familySize: 6,
);

final _emptyPlan = DayPlan(
  priorities: const [],
  dueContacts: const [],
  overdueContacts: const [],
  chaseReferrals: const [],
  generatedAt: DateTime(2026, 9, 1, 6),
);

final _accountProvider = StateProvider<AppUser?>((_) => _user);
final _showShellProvider = StateProvider<bool>((_) => true);

Future<ProviderContainer> _pumpShell(
  WidgetTester tester, {
  Size size = const Size(390, 1400),
  AppUser? user,
  _WarmupHarness? warmup,
}) async {
  final models = warmup ?? _WarmupHarness();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        _accountProvider.overrideWith((_) => user ?? _user),
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
        visibleHouseholdsProvider.overrideWith((ref) async => [_household]),
        dayPlanProvider.overrideWith((ref) async => _emptyPlan),
        openReferralsProvider.overrideWith((ref) async => const []),
        activeClinicSessionProvider.overrideWith((ref) async => null),
        clinicQueueProvider.overrideWith((ref) async => const []),
        householdProvider.overrideWith((ref, id) async => _household),
        zoneHomeChecksProvider.overrideWith((ref) async => const []),
        dailyRegisterProvider.overrideWith(
          (ref) async => const DailyRegisterTally(),
        ),
        syncStatusProvider.overrideWith(
          (ref) => Stream.value(
            const SyncStatusSummary(pending: 0, failing: 0, criticalPending: 0),
          ),
        ),
        connectivityProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Consumer(
          builder: (context, ref, _) => ref.watch(_showShellProvider)
              ? const FhwHome()
              : const SizedBox.shrink(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  for (final language in ['Hausa', 'Twi']) {
    testWidgets('FHW shell entry silently warms only $language', (
      tester,
    ) async {
      final models = _WarmupHarness();
      final container = await _pumpShell(
        tester,
        user: _user.copyWith(preferredLanguage: language),
        warmup: models,
      );

      expect(models.neural.isLoaded(language), isTrue);
      expect(models.piper.supportsLanguage(language), isTrue);
      expect(models.log.loads, ['translation:$language', 'piper:$language']);
      expect(models.log.maxActive, 1);
      expect(models.log.nonLoadingCalls, isEmpty);
      expect(container.read(narrationEnabledProvider), isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  for (final fails in [false, true]) {
    testWidgets(
      'offline runtime guard declines ${fails ? 'errors' : 'uncached runtime'}',
      (tester) async {
        final models = _WarmupHarness()
          ..runtimeCached = false
          ..runtimeError = fails;
        final container = await _pumpShell(
          tester,
          user: _user.copyWith(preferredLanguage: 'Hausa'),
          warmup: models,
        );
        expect(models.log.loads, isEmpty);
        expect(models.neural.isLoaded('Hausa'), isFalse);
        expect(models.piper.supportsLanguage('Hausa'), isFalse);
        expect(tester.takeException(), isNull);

        models.runtimeCached = true;
        models.runtimeError = false;
        container.read(_accountProvider.notifier).state = _user.copyWith(
          preferredLanguage: 'Twi',
        );
        await tester.pump();
        await tester.pumpAndSettle();
        expect(models.neural.isLoaded('Twi'), isTrue);
        expect(models.piper.supportsLanguage('Twi'), isTrue);
      },
    );
  }

  testWidgets(
    'offline runtime check completion cannot warm a superseded language',
    (tester) async {
      final models = _WarmupHarness();
      final gate = models.runtimeGate = Completer<void>();
      final container = await _pumpShell(
        tester,
        user: _user.copyWith(preferredLanguage: 'Hausa'),
        warmup: models,
      );
      expect(models.log.loads, isEmpty);
      container.read(_accountProvider.notifier).state = _user.copyWith(
        preferredLanguage: 'Twi',
      );
      await tester.pumpAndSettle();
      gate.complete();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(models.log.loads, ['translation:Twi', 'piper:Twi']);
      expect(models.log.maxActive, 1);
    },
  );

  testWidgets('offline runtime check cannot start loading after shell exit', (
    tester,
  ) async {
    final models = _WarmupHarness();
    final gate = models.runtimeGate = Completer<void>();
    final container = await _pumpShell(
      tester,
      user: _user.copyWith(preferredLanguage: 'Hausa'),
      warmup: models,
    );
    expect(models.log.loads, isEmpty);
    container.read(_showShellProvider.notifier).state = false;
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(models.log.loads, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('language changes warm the new preference without narration', (
    tester,
  ) async {
    final models = _WarmupHarness();
    final container = await _pumpShell(tester, warmup: models);
    expect(models.log.loads, isEmpty);

    for (final language in ['Hausa', 'Twi']) {
      container.read(_accountProvider.notifier).state = _user.copyWith(
        preferredLanguage: language,
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(models.neural.isLoaded(language), isTrue);
      expect(models.piper.supportsLanguage(language), isTrue);
    }
    expect(models.neural.isLoaded('Hausa'), isFalse);
    expect(models.piper.supportsLanguage('Hausa'), isFalse);
    expect(models.log.loads, [
      'translation:Hausa',
      'piper:Hausa',
      'translation:Twi',
      'piper:Twi',
    ]);
    expect(models.log.nonLoadingCalls, isEmpty);
    expect(container.read(narrationEnabledProvider), isFalse);
  });

  testWidgets('unsupported preferences and non-FHW accounts never warm', (
    tester,
  ) async {
    final models = _WarmupHarness();
    final container = await _pumpShell(tester, warmup: models);
    for (final language in ['English', 'Dagbani', 'French', '']) {
      container.read(_accountProvider.notifier).state = _user.copyWith(
        preferredLanguage: language,
      );
      await tester.pumpAndSettle();
    }
    container.read(_accountProvider.notifier).state = AppUser.fromMap({
      ..._user.toMap(),
      'role': 'caregiver',
      'preferred_language': 'Twi',
    });
    await tester.pumpAndSettle();
    container.read(_accountProvider.notifier).state = null;
    await tester.pumpAndSettle();
    expect(models.log.loads, isEmpty);
    expect(models.log.nonLoadingCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a switch skips stale Piper work and serializes the new language',
    (tester) async {
      final models = _WarmupHarness();
      final gate = models.translation.gate = Completer<void>();
      final container = await _pumpShell(
        tester,
        user: _user.copyWith(preferredLanguage: 'Hausa'),
        warmup: models,
      );
      expect(find.text('Receive patient'), findsOneWidget);
      expect(models.neural.isLoaded('Hausa'), isFalse);
      expect(models.piper.supportsLanguage('Hausa'), isFalse);
      expect(models.log.loads, ['translation:Hausa']);

      container.read(_accountProvider.notifier).state = _user.copyWith(
        preferredLanguage: 'Twi',
      );
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
      expect(models.neural.isLoaded('Twi'), isTrue);
      expect(models.piper.supportsLanguage('Twi'), isTrue);
      expect(models.piper.supportsLanguage('Hausa'), isFalse);
    },
  );

  testWidgets('rapid switches coalesce and reuse an in-flight language load', (
    tester,
  ) async {
    final models = _WarmupHarness();
    final gate = models.translation.gate = Completer<void>();
    final container = await _pumpShell(
      tester,
      user: _user.copyWith(preferredLanguage: 'Hausa'),
      warmup: models,
    );
    for (final language in ['Twi', 'English', 'Hausa', ' ha ']) {
      container.read(_accountProvider.notifier).state = _user.copyWith(
        preferredLanguage: language,
      );
      await tester.pumpAndSettle();
    }
    expect(models.log.loads, ['translation:Hausa']);
    gate.complete();
    await tester.pumpAndSettle();
    expect(models.log.loads, ['translation:Hausa', 'piper:Hausa']);
    expect(models.piper.supportsLanguage('Hausa'), isTrue);
    expect(models.log.maxActive, 1);

    container.read(_accountProvider.notifier).state = _user.copyWith(
      preferredLanguage: 'Hausa',
      facilityName: 'Updated',
    );
    await tester.pumpAndSettle();
    expect(models.log.loads, ['translation:Hausa', 'piper:Hausa']);
  });

  testWidgets('a new language waits for an already-started Piper load', (
    tester,
  ) async {
    final models = _WarmupHarness();
    final gate = models.voice.gate = Completer<void>();
    final container = await _pumpShell(
      tester,
      user: _user.copyWith(preferredLanguage: 'Hausa'),
      warmup: models,
    );
    expect(models.log.loads, ['translation:Hausa', 'piper:Hausa']);
    container.read(_accountProvider.notifier).state = _user.copyWith(
      preferredLanguage: 'Twi',
    );
    await tester.pumpAndSettle();
    expect(models.log.loads, ['translation:Hausa', 'piper:Hausa']);
    gate.complete();
    await tester.pumpAndSettle();
    expect(models.log.loads, [
      'translation:Hausa',
      'piper:Hausa',
      'translation:Twi',
      'piper:Twi',
    ]);
    expect(models.log.maxActive, 1);
    expect(models.piper.supportsLanguage('Twi'), isTrue);
  });

  for (final leave in ['English', 'sign-out', 'shell-exit', 'caregiver']) {
    testWidgets(
      '$leave cancels pending warm-up without disposing shared models',
      (tester) async {
        final models = _WarmupHarness();
        final gate = models.translation.gate = Completer<void>();
        final container = await _pumpShell(
          tester,
          user: _user.copyWith(preferredLanguage: 'Hausa'),
          warmup: models,
        );
        expect(models.log.loads, ['translation:Hausa']);
        if (leave == 'shell-exit') {
          container.read(_showShellProvider.notifier).state = false;
        } else {
          container.read(_accountProvider.notifier).state = switch (leave) {
            'sign-out' => null,
            'caregiver' => AppUser.fromMap({
              ..._user.toMap(),
              'role': 'caregiver',
              'preferred_language': 'Hausa',
            }),
            _ => _user.copyWith(preferredLanguage: 'English'),
          };
        }
        await tester.pumpAndSettle();
        gate.complete();
        await tester.pumpAndSettle();
        expect(models.log.loads, ['translation:Hausa']);
        expect(models.neural.isLoaded('Hausa'), isTrue);
        expect(models.piper.supportsLanguage('Hausa'), isFalse);
        expect(models.log.nonLoadingCalls, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('shell reentry shares the queue while an old load is finishing', (
    tester,
  ) async {
    final models = _WarmupHarness();
    final gate = models.voice.gate = Completer<void>();
    final container = await _pumpShell(
      tester,
      user: _user.copyWith(preferredLanguage: 'Hausa'),
      warmup: models,
    );
    expect(models.log.loads, ['translation:Hausa', 'piper:Hausa']);
    container.read(_showShellProvider.notifier).state = false;
    await tester.pumpAndSettle();
    container.read(_accountProvider.notifier).state = _user.copyWith(
      preferredLanguage: 'Twi',
    );
    container.read(_showShellProvider.notifier).state = true;
    await tester.pumpAndSettle();
    expect(models.log.loads, ['translation:Hausa', 'piper:Hausa']);
    gate.complete();
    await tester.pumpAndSettle();
    expect(models.log.maxActive, 1);
    expect(models.piper.supportsLanguage('Twi'), isTrue);
    expect(models.neural.isLoaded('Twi'), isTrue);
    expect(models.log.nonLoadingCalls, isEmpty);
  });

  testWidgets(
    'failed packs stay unavailable and a later language still warms',
    (tester) async {
      final models = _WarmupHarness();
      models.translation.failures.add('Hausa');
      models.voice.failures.add('Hausa');
      final container = await _pumpShell(
        tester,
        user: _user.copyWith(preferredLanguage: 'Hausa'),
        warmup: models,
      );
      expect(models.log.loads, ['translation:Hausa', 'piper:Hausa']);
      expect(models.neural.isLoaded('Hausa'), isFalse);
      expect(models.piper.supportsLanguage('Hausa'), isFalse);
      expect(tester.takeException(), isNull);
      container.read(_accountProvider.notifier).state = _user.copyWith(
        preferredLanguage: 'Twi',
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(models.neural.isLoaded('Twi'), isTrue);
      expect(models.piper.supportsLanguage('Twi'), isTrue);
      expect(models.log.nonLoadingCalls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unexpected runtime errors do not escape or block the other service',
    (tester) async {
      final models = _WarmupHarness();
      models.translation.throwAvailability = true;
      final container = await _pumpShell(
        tester,
        user: _user.copyWith(preferredLanguage: 'Hausa'),
        warmup: models,
      );
      expect(models.neural.isLoaded('Hausa'), isFalse);
      expect(models.piper.supportsLanguage('Hausa'), isTrue);
      expect(tester.takeException(), isNull);
      models.translation.throwAvailability = false;
      models.voice.throwAvailability = true;
      container.read(_accountProvider.notifier).state = _user.copyWith(
        preferredLanguage: 'Twi',
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(models.neural.isLoaded('Twi'), isTrue);
      expect(models.piper.supportsLanguage('Twi'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the clinic header builds instead of collapsing the shell', (
    tester,
  ) async {
    await _pumpShell(tester);

    expect(tester.takeException(), isNull);
    expect(find.text(_longZone), findsOneWidget);
    expect(find.text('Amina'), findsOneWidget);
  });

  testWidgets('a header that builds leaves the tab body on screen', (
    tester,
  ) async {
    await _pumpShell(tester);

    // The grey-panel symptom was the *body* disappearing with the header, so
    // the header alone is not enough evidence: pin one control from each.
    expect(find.text('Receive patient'), findsOneWidget);
    expect(
      find.textContaining('does not rule out urgent care needs'),
      findsOneWidget,
    );
  });

  testWidgets(
    'the header carries the queue, the record count and the sync line',
    (tester) async {
      await _pumpShell(tester);

      // The queue badge is the dashboard's one way into the live queue now the
      // register card is gone; the record inventory and the honest sync readout
      // moved up from the old second hero, so the tab became a single panel with
      // nothing lost.
      expect(find.text('Queue clear'), findsOneWidget);
      expect(find.text('1 on record'), findsOneWidget);
      expect(
        find.text('Network available · No items waiting to send'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a long zone stays on one line inside the header', (
    tester,
  ) async {
    await _pumpShell(tester);

    final text = tester.widget<Text>(find.text(_longZone));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    // The line has a ceiling of its own, which is what gives the ellipsis
    // something to work against; without it the `Wrap` hands it infinity.
    expect(tester.getSize(find.text(_longZone)).width, lessThanOrEqualTo(220));
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
