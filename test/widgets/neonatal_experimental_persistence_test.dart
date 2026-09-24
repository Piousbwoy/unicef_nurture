// A real neonatal graph run is saved, then re-read from SQLite after the
// database has been closed and reopened. That round trip runs against the
// AppDatabase singleton, whose `_opening` completer survives `close()`: an
// open started inside another test's fake-async zone can never complete, so a
// later `database` await in *this* test would hang the whole file. Keeping the
// only singleton-touching assessment test in its own file is what the other
// AppDatabase tests in this repo already do.
import 'dart:convert';
import 'dart:io';
import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/data/local/app_database.dart';
import 'package:carebridge_ai/data/local/visit_dao.dart';
import 'package:carebridge_ai/data/repositories/care_repository.dart';
import 'package:carebridge_ai/core/ml/offline_inference_service.dart';
import 'package:carebridge_ai/core/ml/tflite_runner_stub.dart' as web_runtime;
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/assessment/assessment_feature_adapter.dart';
import 'package:carebridge_ai/presentation/assessment/result_screen.dart';
import 'package:carebridge_ai/presentation/assessment/types.dart';
import 'package:carebridge_ai/presentation/shared/premium_cards/ai_insight_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _household = Household(
  id: 'h1',
  name: 'Test household',
  region: 'Northern',
  district: 'Gushegu',
  community: 'Gushegu',
  createdBy: 'u1',
);

AssessmentContext _context() => AssessmentContext(
  user: AppUser(
    id: 'u1',
    fullName: 'Test nurse',
    phone: '0244000000',
    role: UserRole.frontlineHealthWorker,
    region: 'Northern',
    district: 'Gushegu',
    community: 'Gushegu',
  ),
  household: _household,
  person: Person(
    id: 'p1',
    householdId: 'h1',
    fullName: 'Test patient',
    clientType: ClientType.newborn,
    dateOfBirth: DateTime.now().subtract(const Duration(days: 2)),
  ),
);

AssessmentDraft _draft(Map<String, Object?> inputs) => AssessmentDraft(
  inputs: inputs,
  result: const AssessmentResult(
    clientType: ClientType.newborn,
    triage: TriageLevel.routine,
    classification: 'WELL NEWBORN — NO IMCI CLASSIFICATION',
    findings: [],
    actions: [],
    dangerSignsPresent: [],
    confidence: RecommendationConfidence.high,
  ),
);

class _CaptureRepository extends CareRepository {
  Assessment? assessment;

  @override
  Future<void> saveAssessment(
    AppUser user,
    Assessment assessment, {
    Referral? referral,
    List<ScheduledContact> followUps = const [],
  }) async {
    this.assessment = assessment;
  }
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets(
    'real graph result survives SQLite close and reload independently',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final dir = Directory('.dart_tool').createTempSync('neural-assessment-');
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'getApplicationDocumentsDirectory'
            ? dir.absolute.path
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      addTearDown(() async {
        await AppDatabase.instance.close();
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      await tester.runAsync(() async {
        AppDatabase.initialiseForDesktopAndTests();
        await AppDatabase.instance.close();
        await AppDatabase.instance.database;
      });

      final draft = _draft({
        'age_in_days': 2,
        'temperature_celsius': 37.0,
        'respiratory_rate': 48,
        'pulse': 140,
        'weight_kg': 3.0,
        'danger_signs': <String>[],
      });
      // Genuine inference from the shipped artifact, via the pure-Dart runner so
      // this test does not depend on the bundled native library.
      final outputs = await tester.runAsync(
        () => OfflineInferenceService(runner: web_runtime.createTfliteRunner())
            .runAllPredictions(
              AssessmentFeatureAdapter(_context(), draft).features,
              includeChildPneumonia: false,
              includePreeclampsia: false,
              includeLbwSga: false,
            ),
      );
      expect(
        outputs!['neonatal_sepsis']!.mayDisplayExperimentalOutput,
        isTrue,
        reason: outputs['neonatal_sepsis']!.statusReason,
      );
      final prediction = outputs['neonatal_sepsis']!;

      final repository = _CaptureRepository();
      tester.view.physicalSize = const Size(1080, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bootstrapProvider.overrideWith((ref) async {}),
            careRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            home: AssessmentResultScreen(
              input: _context(),
              draft: draft,
              visitId: 'v1',
              // The real prediction is already in hand; the screen only needs to
              // render it, so no inference service runs here.
              inferenceService: _ResolvedService(prediction),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Experimental model score'), findsOneWidget);
      final card = tester.widget<AiInsightCard>(find.byType(AiInsightCard));
      expect(
        card.reasoning.experimentalAssessment!.prediction,
        same(prediction),
      );
      expect(prediction.rawNeuralOutput, closeTo(.578125, 1e-5));
      expect(prediction.researchOutput, closeTo(.005530982066298801, 1e-5));
      // Experimental output must not move protocol-driven care.
      expect(find.text('Pre-referral stabilisation'), findsNothing);

      await tester.tap(find.text('Save assessment'));
      await tester.pumpAndSettle();
      final saved = repository.assessment!;
      final snapshot =
          (saved.inputs['ml_predictions'] as Map)['neonatal_sepsis'] as Map;
      expect(snapshot['observed_values'], hasLength(5));
      expect(snapshot['fixed_features'], hasLength(15));
      expect(snapshot['sensitivities'], hasLength(5));
      expect(
        snapshot['artifact_sha256'],
        OfflineInferenceService.neonatalArtifact,
      );
      expect(
        snapshot['input_policy_version'],
        OfflineInferenceService.neonatalPolicy,
      );
      expect(snapshot['experimental_raw_output'], prediction.rawNeuralOutput);
      expect(
        snapshot['experimental_adjusted_output'],
        prediction.researchOutput,
      );

      await tester.runAsync(() async {
        final db = await AppDatabase.instance.database;
        final context = _context();
        await db.insert(Tables.users, context.user.toMap());
        await db.insert(Tables.households, _household.toMap());
        await db.insert(Tables.persons, context.person.toMap());
        await db.insert(
          Tables.visits,
          Visit(
            id: 'v1',
            householdId: 'h1',
            conductedBy: 'u1',
            startedAt: DateTime(2026, 8, 1),
            reasons: const [],
          ).toMap(),
        );
        await AssessmentDao.save(saved);
        final legacyRow = saved.toMap()
          ..['id'] = 'legacy-assessment'
          ..['inputs_json'] = jsonEncode({'temperature_celsius': 37})
          ..['care_plan_json'] = null;
        await db.insert(Tables.assessments, legacyRow);
        await AppDatabase.instance.close();
        final restored = (await AssessmentDao.byId(saved.id))!;
        expect(restored.inputs, saved.inputs);
        expect(restored.result.toJson(), saved.result.toJson());
        expect(restored.carePlanJson, saved.carePlanJson);
        expect(restored.result.findings, isEmpty);
        expect(
          restored.carePlanJson,
          isNot(contains('experimental_adjusted_output')),
        );
        final legacy = (await AssessmentDao.byId('legacy-assessment'))!;
        expect(legacy.inputs, {'temperature_celsius': 37});
        expect(legacy.inputs.containsKey('ml_predictions'), isFalse);
        expect(legacy.carePlanJson, isNull);
        expect(legacy.result.toJson(), saved.result.toJson());
      });
    },
  );
}

/// Hands the screen the prediction it would otherwise compute, so the widget
/// path under test is display + persistence rather than a second inference run.
class _ResolvedService extends OfflineInferenceService {
  _ResolvedService(this.prediction)
    : super(runner: web_runtime.createTfliteRunner());

  final OfflineRiskPrediction prediction;

  @override
  Future<List<OfflineModelStatus>> modelStatuses() async => [];

  @override
  Future<Map<String, OfflineRiskPrediction>> runAllPredictions(
    OfflineFeatureBag bag, {
    bool includeNeonatal = true,
    bool includeChildPneumonia = true,
    bool includePreeclampsia = true,
    bool includeLbwSga = true,
  }) async => {'neonatal_sepsis': prediction};
}
