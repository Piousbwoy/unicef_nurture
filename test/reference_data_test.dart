/// The Northern Ghana reference dataset: the research that grounds the app
/// in real administrative geography rather than placeholder strings.
library;

import 'package:carebridge_ai/data/reference/northern_ghana.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NorthernGhana reference data', () {
    test('covers the five northern regions', () {
      expect(
        NorthernGhana.regionNames,
        containsAll([
          'Northern Region',
          'North East Region',
          'Savannah Region',
          'Upper East Region',
          'Upper West Region',
        ]),
      );
    });

    test('every region has districts, every district has communities', () {
      for (final region in NorthernGhana.regions) {
        expect(region.districts, isNotEmpty, reason: region.name);
        for (final district in region.districts) {
          expect(
            district.communities,
            isNotEmpty,
            reason: '${region.name} / ${district.name}',
          );
        }
      }
    });

    test('the cascade lookups agree with the raw data', () {
      const region = 'Northern Region';
      final districts = NorthernGhana.districtsOf(region);
      expect(districts, isNotEmpty);

      final first = districts.first.name;
      expect(NorthernGhana.communitiesOf(region, first), isNotEmpty);
      expect(NorthernGhana.communitiesOf(region, 'No Such District'), isEmpty);
    });

    test('language lists always include the trade and official languages', () {
      for (final region in NorthernGhana.regionNames) {
        final langs = NorthernGhana.languagesOf(region);
        expect(langs, contains('English'), reason: region);
        expect(langs, contains('Hausa'), reason: region);
      }
    });

    test('Dagbani leads in the Northern Region', () {
      expect(NorthernGhana.languagesOf('Northern Region').first, 'Dagbani');
    });
  });
}
