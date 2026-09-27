import 'package:flutter_test/flutter_test.dart';
import 'package:navguide/features/nearby/nearby_places_service.dart';

void main() {
  group('Vidyarthi Bhavan and Near Me Search Tests', () {
    final service = NearbyPlacesService();

    test('getInstantPlaces returns Vidyarthi Bhavan even when user is far away (Hebbal 14.5km)', () {
      // User is at Hebbal / North Bangalore (lat: 13.0364, lng: 77.6666)
      final results = service.getInstantPlaces(
        userLat: 13.0364,
        userLng: 77.6666,
        maxRadiusKm: 5.0, // Default 5km radius should not hide explicitly searched destination
        searchQuery: 'Vidyarthi Bhavan',
      );

      expect(results, isNotEmpty);
      final vb = results.firstWhere((p) => p.name.contains('Vidyarthi Bhavan'));
      expect(vb.name, contains('Vidyarthi Bhavan'));
      expect(vb.address, contains('Gandhi Bazaar'));
      expect(vb.address, contains('Basavanagudi'));
      expect(vb.latitude, closeTo(12.9450, 0.005));
      expect(vb.longitude, closeTo(77.5715, 0.005));
      // Distance is ~14.5 km, which should be properly retained and formatted
      expect(vb.distanceMeters, greaterThan(10000));
    });

    test('getInstantPlaces differentiates cache keys when searchQuery changes', () {
      final allPlaces = service.getInstantPlaces(
        userLat: 13.0364,
        userLng: 77.6666,
        maxRadiusKm: 5.0,
        searchQuery: '',
      );

      final vbSearch = service.getInstantPlaces(
        userLat: 13.0364,
        userLng: 77.6666,
        maxRadiusKm: 5.0,
        searchQuery: 'Vidyarthi Bhavan',
      );

      expect(vbSearch.any((p) => p.name.contains('Vidyarthi Bhavan')), isTrue);
      // All places should be different from targeted search
      expect(allPlaces.length != vbSearch.length || allPlaces.first.id != vbSearch.first.id, isTrue);
    });
  });
}
