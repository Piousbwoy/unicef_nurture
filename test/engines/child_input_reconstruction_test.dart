/// Getting the counterfactual onto the screen without letting it lie.
///
/// The counterfactual engine needs a [ChildInput], but the result screen holds a
/// *stored measurement map* — and it renders saved records as well as live ones,
/// so there is no input object to thread through. Reconstructing one is only safe
/// because the form stores the very values it read when it classified:
/// `danger_signs` holds the same tokens, `respiratory_rate` the same count.
///
/// That is an "only if", not an "as long as". So the reconstruction is gated: the
/// rebuilt input is re-assessed, and unless its verdict equals the verdict we
/// stored, the caller gets `null` and shows nothing. A counterfactual computed
/// from an input that disagrees with the record on screen would be worse than
/// none — a second, quieter opinion contradicting the first.
library;

import 'package:carebridge_ai/domain/engines/child_engine.dart';
import 'package:carebridge_ai/domain/engines/child_input_from_record.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

/// The record as `child_form.dart` writes it for an IMCI child visit.
Map<String, Object?> childMap({
  int? ageMonths = 14,
  int? rr = 62,
  double? temp = 38.2,
  List<String> signs = const ['cough'],
  String protocol = 'imci_child',
  double? muacCm = 12.8,
  int? muacMm,
}) => {
  'protocol': protocol,
  'age_in_months': ageMonths,
  'respiratory_rate': rr,
  'temperature_celsius': temp,
  'danger_signs': signs,
  'weight_kg': 9.4,
  'muac_cm': muacCm,
  'muac_mm': muacMm,
  'has_oedema': false,
  'rdt_done': false,
  'rdt_positive': null,
  'skin_pinch_result': 'none',
};

/// The verdict the engine reaches for those same values, typed the way the form
/// types them. Tests ask for *this* string as the stored one, so a positive case
/// proves map and input carry identical information — it does not quietly assume
/// the engine's output.
String verdictOf(ChildInput input) => ChildEngine.assess(input).classification;

const _pneumoniaInput = ChildInput(
  ageInMonths: 14,
  respiratoryRate: 62,
  temperatureCelsius: 38.2,
  weightKg: 9.4,
  muacCm: 12.8,
  cough: true,
);

void main() {
  group('reconstruction is gated on the stored verdict', () {
    test('a map that reproduces the stored classification is usable', () {
      final input = ChildInputReconstruction.forCounterfactual(
        inputs: childMap(),
        storedClassification: verdictOf(_pneumoniaInput),
      );
      expect(input, isNotNull);
      expect(input!.ageInMonths, 14);
      expect(input.respiratoryRate, 62);
      expect(input.cough, isTrue);
    });

    test('a map that contradicts the stored verdict yields nothing', () {
      // The record claims a healthy child while the rate and cough say
      // otherwise: something the classifier saw is missing from the map, so we
      // refuse to speculate about which measurement would flip the call.
      final input = ChildInputReconstruction.forCounterfactual(
        inputs: childMap(),
        storedClassification: 'WELL CHILD',
      );
      expect(input, isNull);
    });

    test('no age means no thresholds, and therefore no counterfactual', () {
      // Under 12 months the cut-off is 50/min, from 12 months it is 40/min. The
      // same rate answers a different question, so age is not optional here.
      final input = ChildInputReconstruction.forCounterfactual(
        inputs: {...childMap(), 'age_in_months': null},
        storedClassification: verdictOf(_pneumoniaInput),
      );
      expect(input, isNull);
    });

    test('a non-child protocol is refused, not forced through the child engine', () {
      // 'young_infant' is the tag the young-infant form actually writes: same
      // field names, different protocol, different thresholds.
      final input = ChildInputReconstruction.forCounterfactual(
        inputs: childMap(protocol: 'young_infant'),
        storedClassification: verdictOf(_pneumoniaInput),
      );
      expect(input, isNull);
    });
  });

  group('the map is read the way the form wrote it', () {
    test('danger-sign tokens land on their own fields', () {
      const severe = ChildInput(
        ageInMonths: 14,
        respiratoryRate: 58,
        temperatureCelsius: 38.2,
        weightKg: 9.4,
        muacCm: 12.8,
        cough: true,
        chestIndrawing: true,
        vomitsEverything: true,
      );
      final input = ChildInputReconstruction.forCounterfactual(
        inputs: childMap(
          signs: const ['cough', 'indrawing', 'vomitsAll'],
          rr: 58,
        ),
        storedClassification: verdictOf(severe),
      );
      expect(input, isNotNull);
      expect(input!.chestIndrawing, isTrue);
      expect(input.vomitsEverything, isTrue);
      expect(input.convulsions, isFalse);
    });

    test('a maternal map is refused rather than treated as empty', () {
      final input = ChildInputReconstruction.forCounterfactual(
        inputs: const {'protocol': 'anc', 'age_in_months': null},
        storedClassification: 'ECLAMPSIA',
      );
      expect(input, isNull);
    });

    test('junk in a numeric field cannot throw', () {
      // A row restored from an older build can hold a string or nonsense. The
      // gate closes quietly — an unreadable rate changes the verdict, so the
      // reconstruction is refused rather than guessed.
      final input = ChildInputReconstruction.forCounterfactual(
        inputs: {...childMap(), 'respiratory_rate': 'not-a-number'},
        storedClassification: verdictOf(_pneumoniaInput),
      );
      expect(input, isNull);
    });

    test('muac arrives in centimetres, whether the map stored mm or cm', () {
      // 12.8 cm keeps the classification identical, so this test measures the
      // unit conversion alone instead of stumbling over a malnutrition verdict.
      final fromMm = ChildInputReconstruction.forCounterfactual(
        inputs: childMap(muacCm: null, muacMm: 128),
        storedClassification: verdictOf(_pneumoniaInput),
      );
      expect(fromMm, isNotNull);
      expect(fromMm!.muacCm, closeTo(12.8, 0.001));
    });
  });

  group('the client type decides whether we try at all', () {
    test('only the 2–59 month child protocol is reconstructible', () {
      expect(
        ChildInputReconstruction.supports(ClientType.childUnderFive),
        isTrue,
      );
      expect(ChildInputReconstruction.supports(ClientType.newborn), isFalse);
      expect(
        ChildInputReconstruction.supports(ClientType.pregnantWoman),
        isFalse,
      );
      expect(
        ChildInputReconstruction.supports(ClientType.postpartumWoman),
        isFalse,
      );
      expect(
        ChildInputReconstruction.supports(ClientType.womanOfReproductiveAge),
        isFalse,
      );
    });
  });
}
