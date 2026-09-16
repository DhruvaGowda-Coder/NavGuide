import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

class PlaceResult {
  const PlaceResult({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.category = 'Destination',
  });

  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String category;
}

class PlaceSearchService {
  PlaceSearchService({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  // Curated prominent Bangalore destinations for instant 0ms offline search
  static const List<PlaceResult> popularBangalorePlaces = [
    PlaceResult(
      name: 'Kempegowda International Airport (BLR)',
      address: 'KIAL Rd, Devanahalli, Bengaluru',
      latitude: 13.1986,
      longitude: 77.7066,
      category: 'Airport',
    ),
    PlaceResult(
      name: 'MG Road Metro & Brigade Road',
      address: 'MG Road, Central Business District, Bengaluru',
      latitude: 12.9756,
      longitude: 77.6066,
      category: 'Commercial Hub',
    ),
    PlaceResult(
      name: 'Indiranagar 100 Feet Road',
      address: 'Indiranagar, East Bengaluru',
      latitude: 12.9719,
      longitude: 77.6412,
      category: 'Dining & Shopping',
    ),
    PlaceResult(
      name: 'Koramangala 80 Feet Road',
      address: 'Koramangala 4th Block, Bengaluru',
      latitude: 12.9352,
      longitude: 77.6245,
      category: 'Startup & Tech Hub',
    ),
    PlaceResult(
      name: 'Whitefield (ITPL)',
      address: 'International Tech Park, Whitefield, Bengaluru',
      latitude: 12.9863,
      longitude: 77.7314,
      category: 'IT Park',
    ),
    PlaceResult(
      name: 'Electronic City Phase 1',
      address: 'Hosur Road, Electronic City, Bengaluru',
      latitude: 12.8452,
      longitude: 77.6602,
      category: 'IT Hub',
    ),
    PlaceResult(
      name: 'Silk Board Junction',
      address: 'Central Silk Board, Hosur Road, Bengaluru',
      latitude: 12.9177,
      longitude: 77.6238,
      category: 'Transit Junction',
    ),
    PlaceResult(
      name: 'Majestic (KSR Railway Station)',
      address: 'Kempegowda Bus Station, Majestic, Bengaluru',
      latitude: 12.9778,
      longitude: 77.5713,
      category: 'Transit Hub',
    ),
    PlaceResult(
      name: 'Hebbal Flyover Junction',
      address: 'Bellary Road, Hebbal, North Bengaluru',
      latitude: 13.0358,
      longitude: 77.5970,
      category: 'North Gateway',
    ),
    PlaceResult(
      name: 'Manyata Tech Park',
      address: 'Outer Ring Road, Nagavara, Bengaluru',
      latitude: 13.0478,
      longitude: 77.6200,
      category: 'IT Park',
    ),
    PlaceResult(
      name: 'Jayanagar 4th Block Complex',
      address: 'Jayanagar, South Bengaluru',
      latitude: 12.9298,
      longitude: 77.5833,
      category: 'Market & Residential',
    ),
    PlaceResult(
      name: 'Malleshwaram 8th Cross',
      address: 'Sampige Road, Malleshwaram, Bengaluru',
      latitude: 13.0031,
      longitude: 77.5707,
      category: 'Heritage Market',
    ),
    PlaceResult(
      name: 'HSR Layout Sector 1',
      address: 'HSR Layout, Southeast Bengaluru',
      latitude: 12.9121,
      longitude: 77.6446,
      category: 'Residential & Startups',
    ),
    PlaceResult(
      name: 'Marathahalli Bridge',
      address: 'Outer Ring Road & Varthur Road, Bengaluru',
      latitude: 12.9569,
      longitude: 77.7011,
      category: 'ORR Junction',
    ),
    PlaceResult(
      name: 'Bannerghatta National Park',
      address: 'Bannerghatta Main Road, Bengaluru',
      latitude: 12.8009,
      longitude: 77.5777,
      category: 'Leisure',
    ),
    PlaceResult(
      name: 'Bellandur EcoSpace',
      address: 'Outer Ring Road, Bellandur, Bengaluru',
      latitude: 12.9260,
      longitude: 77.6762,
      category: 'IT Corridor',
    ),
  ];

  /// Search places matching query via local instant index + OpenStreetMap live lookup
  Future<List<PlaceResult>> searchPlaces(String query) async {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return popularBangalorePlaces;

    // 1. First search local offline database
    final localMatches = popularBangalorePlaces.where((p) {
      return p.name.toLowerCase().contains(clean) ||
          p.address.toLowerCase().contains(clean) ||
          p.category.toLowerCase().contains(clean);
    }).toList();

    // 2. If short query and have good local matches, return early
    if (clean.length < 3 && localMatches.isNotEmpty) {
      return localMatches;
    }

    // 3. Query OpenStreetMap Nominatim for live global/city search
    try {
      final encoded = Uri.encodeComponent('$query, Bengaluru, India');
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=$encoded&format=json&addressdetails=1&limit=5&countrycodes=in',
      );

      final req = await _client.getUrl(uri).timeout(const Duration(seconds: 4));
      req.headers.set('User-Agent', 'NavGuardianAI-FlutterApp/1.0 (navguardian.ai)');
      final res = await req.close().timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final list = jsonDecode(body) as List<dynamic>;

        final apiResults = <PlaceResult>[];
        for (final item in list) {
          final map = item as Map<String, dynamic>;
          final displayName = map['display_name'] as String? ?? '';
          final parts = displayName.split(',');
          final title = parts.isNotEmpty ? parts[0].trim() : displayName;
          final subtitle = parts.length > 1 ? parts.sublist(1, math.min(4, parts.length)).join(',').trim() : displayName;
          final lat = double.tryParse(map['lat']?.toString() ?? '');
          final lon = double.tryParse(map['lon']?.toString() ?? '');

          if (lat != null && lon != null) {
            apiResults.add(
              PlaceResult(
                name: title,
                address: subtitle,
                latitude: lat,
                longitude: lon,
                category: map['type']?.toString().toUpperCase() ?? 'Location',
              ),
            );
          }
        }

        // Merge without duplicates
        final existingNames = localMatches.map((e) => e.name.toLowerCase()).toSet();
        for (final r in apiResults) {
          if (!existingNames.contains(r.name.toLowerCase())) {
            localMatches.add(r);
          }
        }
      }
    } catch (_) {
      // Offline fallback to local matches
    }

    return localMatches;
  }
}
