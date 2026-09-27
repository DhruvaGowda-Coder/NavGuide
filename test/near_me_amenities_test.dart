import 'package:flutter_test/flutter_test.dart';
import 'package:navguide/features/nearby/nearby_places_service.dart';

void main() {
  group('Near Me Super Search Engine & Proximity Tests', () {
    final service = NearbyPlacesService();
    const double bangaloreLat = 12.9716;
    const double bangaloreLng = 77.5946;

    test('Parking category returns rich results and strictly sorted by distance', () {
      final parking50km = service.getInstantPlaces(
        userLat: bangaloreLat,
        userLng: bangaloreLng,
        filterCategory: PlaceCategory.parking,
        maxRadiusKm: 50.0,
      );

      expect(parking50km.length, greaterThanOrEqualTo(15),
          reason: 'At 50km, multiple parking facilities should be found');
      expect(parking50km.every((p) => p.category == PlaceCategory.parking), isTrue);

      // Verify strict ascending distance sorting
      for (int i = 0; i < parking50km.length - 1; i++) {
        expect(parking50km[i].distanceMeters, lessThanOrEqualTo(parking50km[i + 1].distanceMeters),
            reason: 'Places must be strictly ordered from closest to farthest');
      }

      final parking5km = service.getInstantPlaces(
        userLat: bangaloreLat,
        userLng: bangaloreLng,
        filterCategory: PlaceCategory.parking,
        maxRadiusKm: 5.0,
      );
      expect(parking5km.length, greaterThanOrEqualTo(4),
          reason: 'Within 5km, central city parking hubs must be found');
    });

    test('Petrol Pump / Fuel category returns rich results and strictly sorted by distance', () {
      final fuel50km = service.getInstantPlaces(
        userLat: bangaloreLat,
        userLng: bangaloreLng,
        filterCategory: PlaceCategory.fuel,
        maxRadiusKm: 50.0,
      );

      expect(fuel50km.length, greaterThanOrEqualTo(15),
          reason: 'At 50km, rich petrol and fuel stations must be found');
      expect(fuel50km.every((p) => p.category == PlaceCategory.fuel), isTrue);

      for (int i = 0; i < fuel50km.length - 1; i++) {
        expect(fuel50km[i].distanceMeters, lessThanOrEqualTo(fuel50km[i + 1].distanceMeters));
      }

      final fuel5km = service.getInstantPlaces(
        userLat: bangaloreLat,
        userLng: bangaloreLng,
        filterCategory: PlaceCategory.fuel,
        maxRadiusKm: 5.0,
      );
      expect(fuel5km.length, greaterThanOrEqualTo(4));
    });

    test('EV Charging category returns rich results and strictly sorted by distance', () {
      final ev50km = service.getInstantPlaces(
        userLat: bangaloreLat,
        userLng: bangaloreLng,
        filterCategory: PlaceCategory.ev,
        maxRadiusKm: 50.0,
      );

      expect(ev50km.length, greaterThanOrEqualTo(15));
      expect(ev50km.every((p) => p.category == PlaceCategory.ev), isTrue);

      for (int i = 0; i < ev50km.length - 1; i++) {
        expect(ev50km[i].distanceMeters, lessThanOrEqualTo(ev50km[i + 1].distanceMeters));
      }

      final ev5km = service.getInstantPlaces(
        userLat: bangaloreLat,
        userLng: bangaloreLng,
        filterCategory: PlaceCategory.ev,
        maxRadiusKm: 5.0,
      );
      expect(ev5km.length, greaterThanOrEqualTo(4));
    });

    test('Restaurants return rich results and strictly sorted by distance', () {
      final rest50km = service.getInstantPlaces(
        userLat: bangaloreLat,
        userLng: bangaloreLng,
        filterCategory: PlaceCategory.restaurant,
        maxRadiusKm: 50.0,
      );

      expect(rest50km.length, greaterThanOrEqualTo(15));
      expect(rest50km.every((p) => p.category == PlaceCategory.restaurant), isTrue);

      for (int i = 0; i < rest50km.length - 1; i++) {
        expect(rest50km[i].distanceMeters, lessThanOrEqualTo(rest50km[i + 1].distanceMeters));
      }
    });

    test('ATM category returns rich results at 5km and 50km', () {
      final atms50km = service.getInstantPlaces(
        userLat: bangaloreLat,
        userLng: bangaloreLng,
        filterCategory: PlaceCategory.atm,
        maxRadiusKm: 50.0,
      );

      expect(atms50km.length, greaterThanOrEqualTo(10));
      expect(atms50km.every((p) => p.category == PlaceCategory.atm), isTrue);
    });

    test('Public Toilet category returns rich results at 5km and 50km', () {
      final toilets50km = service.getInstantPlaces(
        userLat: bangaloreLat,
        userLng: bangaloreLng,
        filterCategory: PlaceCategory.toilet,
        maxRadiusKm: 50.0,
      );

      expect(toilets50km.length, greaterThanOrEqualTo(10));
      expect(toilets50km.every((p) => p.category == PlaceCategory.toilet), isTrue);
    });

    test('Pharmacy category returns rich results at 5km and 50km', () {
      final pharmacies50km = service.getInstantPlaces(
        userLat: bangaloreLat,
        userLng: bangaloreLng,
        filterCategory: PlaceCategory.pharmacy,
        maxRadiusKm: 50.0,
      );

      expect(pharmacies50km.length, greaterThanOrEqualTo(10));
      expect(pharmacies50km.every((p) => p.category == PlaceCategory.pharmacy), isTrue);
    });
  });
}
