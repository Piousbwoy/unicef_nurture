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

    test('every guidance picker offers exactly the four spoken languages', () {
      for (final region in NorthernGhana.regionNames) {
        expect(
          NorthernGhana.languagesOf(region),
          ['Dagbani', 'Hausa', 'Twi', 'English'],
          reason: region,
        );
      }
    });

    test('Dagbani leads every guidance picker', () {
      for (final region in NorthernGhana.regionNames) {
        expect(NorthernGhana.languagesOf(region).first, 'Dagbani');
      }
    });

    // The CHPS zone picker is the one list that cannot be filtered — a zone
    // follows a care route, not an assembly line — so these assert that
    // nearness is expressed as *order* and never as removal.
    group('the ranked CHPS zone picker', () {
      const tamaleNeighbours = 'Tamale';

      test('leads with the community the worker just chose', () {
        final zones = NorthernGhana.zonesRankedFor(
          regionName: 'Northern Region',
          districtName: tamaleNeighbours,
          community: 'Tamale Central',
        );
        expect(zones.first, 'Tamale Central');
      });

      test('every zone in that district outranks every zone outside it', () {
        final zones = NorthernGhana.zonesRankedFor(
          regionName: 'Northern Region',
          districtName: tamaleNeighbours,
          community: 'Tamale Central',
        );
        final district = NorthernGhana.communitiesOf(
          'Northern Region',
          tamaleNeighbours,
        );
        final firstOutside = zones.firstWhere((z) => !district.contains(z));
        for (final near in district) {
          expect(
            zones.indexOf(near),
            lessThan(zones.indexOf(firstOutside)),
            reason: '$near should sit above $firstOutside',
          );
        }
      });

      test('hides nothing — the whole country is still pickable', () {
        final far = NorthernGhana.regions.last.districts.first;
        final zones = NorthernGhana.zonesRankedFor(
          regionName: NorthernGhana.regions.last.name,
          districtName: far.name,
          community: far.communities.first,
        );
        expect(zones.toSet(), NorthernGhana.allCommunities.toSet());
        expect(zones.length, NorthernGhana.allCommunities.length);
      });

      test('with no context it is the plain alphabetical list', () {
        expect(NorthernGhana.zonesRankedFor(), NorthernGhana.allCommunities);
      });

      test('an unlisted settlement is offered, not dropped', () {
        final zones = NorthernGhana.zonesRankedFor(
          regionName: 'Northern Region',
          districtName: 'No Such District',
          community: 'A hamlet nobody gazetted',
        );
        expect(zones.first, 'A hamlet nobody gazetted');
        expect(zones.length, NorthernGhana.allCommunities.length + 1);
      });
    });
  });
}
