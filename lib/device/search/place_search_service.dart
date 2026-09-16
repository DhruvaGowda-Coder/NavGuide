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

  // Curated prominent Karnataka (Hassan, Chikkamagaluru, Bangalore, etc.) & All-India destinations for instant 0ms offline search
  static const List<PlaceResult> popularIndianPlaces = [
    // Hassan District Places
    PlaceResult(
      name: 'Gavenahalli (Hassan)',
      address: 'Hasana taluk, Hassan District, Karnataka, 573201',
      latitude: 13.0000,
      longitude: 76.1252,
      category: 'Village / Hometown (Hassan)',
    ),
    PlaceResult(
      name: 'Hassan City Central',
      address: 'Hassan City, Hassan District, Karnataka',
      latitude: 13.0072,
      longitude: 76.0965,
      category: 'District Headquarters',
    ),
    PlaceResult(
      name: 'Sakleshpur (Western Ghats)',
      address: 'Hassan District, Karnataka',
      latitude: 12.9439,
      longitude: 75.7877,
      category: 'Hill Station / Plantation Hub',
    ),
    PlaceResult(
      name: 'Belur Chennakeshava Temple',
      address: 'Belur, Hassan District, Karnataka',
      latitude: 13.1623,
      longitude: 75.8596,
      category: 'Hoysala Heritage',
    ),
    PlaceResult(
      name: 'Halebeedu Hoysaleshwara',
      address: 'Hassan District, Karnataka',
      latitude: 13.2136,
      longitude: 75.9936,
      category: 'Heritage Landmark',
    ),
    PlaceResult(
      name: 'Channarayapatna / Shravanabelagola',
      address: 'Hassan District, Karnataka',
      latitude: 12.9066,
      longitude: 76.3926,
      category: 'Heritage & Transit Hub',
    ),

    // Chikkamagaluru District Places
    PlaceResult(
      name: 'Gavanahalli (Chikkamagaluru)',
      address: 'Chikkamagaluru taluku, Chikkamagaluru, Karnataka, 577142',
      latitude: 13.2919,
      longitude: 75.7558,
      category: 'Village (Chikkamagaluru)',
    ),
    PlaceResult(
      name: 'Chikkamagaluru Town',
      address: 'Chikkamagaluru District, Karnataka',
      latitude: 13.3161,
      longitude: 75.7720,
      category: 'Coffee Land / Hill Station',
    ),
    PlaceResult(
      name: 'Mullayanagiri Peak',
      address: 'Chikkamagaluru, Karnataka',
      latitude: 13.3916,
      longitude: 75.7214,
      category: 'Highest Peak in Karnataka',
    ),

    // Bengaluru & Major Karnataka Centers
    PlaceResult(
      name: 'Devanahalli',
      address: 'Bengaluru North / Rural, Karnataka',
      latitude: 13.2483,
      longitude: 77.7126,
      category: 'Historic Town',
    ),
    PlaceResult(
      name: 'Kempegowda International Airport (BLR)',
      address: 'KIAL Rd, Devanahalli, Bengaluru',
      latitude: 13.1986,
      longitude: 77.7066,
      category: 'Airport',
    ),
    PlaceResult(
      name: 'Mysuru Palace',
      address: 'Sayyaji Rao Road, Mysuru, Karnataka',
      latitude: 12.3051,
      longitude: 76.6551,
      category: 'Heritage Palace',
    ),
    PlaceResult(
      name: 'Mangaluru Coastal Port',
      address: 'Dakshina Kannada, Karnataka',
      latitude: 12.9141,
      longitude: 74.8560,
      category: 'Coastal Port City',
    ),
    PlaceResult(
      name: 'Shivamogga (Gateway to Malnad)',
      address: 'Shivamogga District, Karnataka',
      latitude: 13.9299,
      longitude: 75.5681,
      category: 'Malnad Gateway',
    ),
    PlaceResult(
      name: 'Hubballi - Dharwad',
      address: 'Hubballi Junction, North Karnataka',
      latitude: 15.3647,
      longitude: 75.1240,
      category: 'Commercial Hub',
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

    // National Metros & Landmarks
    PlaceResult(
      name: 'Marine Drive',
      address: 'Netaji Subhash Chandra Bose Road, Mumbai, Maharashtra',
      latitude: 18.9438,
      longitude: 72.8232,
      category: 'National Landmark',
    ),
    PlaceResult(
      name: 'Connaught Place',
      address: 'Central Delhi, New Delhi',
      latitude: 28.6315,
      longitude: 77.2167,
      category: 'National Capital Hub',
    ),
    PlaceResult(
      name: 'Hitec City (Cyberabad)',
      address: 'Madhapur, Hyderabad, Telangana',
      latitude: 17.4474,
      longitude: 78.3762,
      category: 'Tech City',
    ),
  ];

  // Backward compatibility alias
  static List<PlaceResult> get popularBangalorePlaces => popularIndianPlaces;

  /// Generates spelling and district variants for search queries
  List<String> _expandQueryVariants(String query) {
    final clean = query.trim().toLowerCase();
    final variants = <String>[clean];

    // Handles user phonetic variations for Gavenahalli / Gavanahalli
    if (clean.contains('gaven') || clean.contains('gavan') || clean.contains('gavean')) {
      variants.add('gavenahalli');
      variants.add('gavenahalli hassan');
      variants.add('gavanahalli');
      variants.add('gavanahalli chikkamagaluru');
    }

    if (clean.contains('chikmag') || clean.contains('chickmag')) {
      variants.add('chikkamagaluru');
    }

    if (clean.contains('hasan') && !clean.contains('hassan')) {
      variants.add('hassan');
    }

    if (clean == 'blr' || clean == 'airport') {
      variants.add('kempegowda international airport');
    }

    return variants.toSet().toList();
  }

  /// Search places matching query across ALL OF INDIA via local instant index + OpenStreetMap live lookup
  Future<List<PlaceResult>> searchPlaces(String query) async {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return popularIndianPlaces;

    final variants = _expandQueryVariants(query);

    // 1. First search local offline database against all variants
    final localMatches = popularIndianPlaces.where((p) {
      final n = p.name.toLowerCase();
      final a = p.address.toLowerCase();
      final c = p.category.toLowerCase();

      for (final v in variants) {
        if (n.contains(v) || a.contains(v) || c.contains(v)) {
          return true;
        }
      }
      return false;
    }).toList();

    // 2. Query OpenStreetMap Nominatim across ALL OF INDIA for the variants
    final apiResults = <PlaceResult>[];
    final queriedUrls = <String>{};

    // We query up to 2 primary variants concurrently to ensure lightning fast response
    final queriesToRun = variants.take(2).toList();

    await Future.wait(
      queriesToRun.map((v) async {
        final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(v)}&format=json&addressdetails=1&limit=6&countrycodes=in',
        );

        if (queriedUrls.contains(uri.toString())) return;
        queriedUrls.add(uri.toString());

        try {
          final req = await _client.getUrl(uri).timeout(const Duration(seconds: 4));
          req.headers.set('User-Agent', 'NavGuardianAI-FlutterApp/1.0 (navguardian.ai)');
          final res = await req.close().timeout(const Duration(seconds: 4));

          if (res.statusCode == 200) {
            final body = await res.transform(utf8.decoder).join();
            final list = jsonDecode(body) as List<dynamic>;

            for (final item in list) {
              final map = item as Map<String, dynamic>;
              final displayName = map['display_name'] as String? ?? '';
              final parts = displayName.split(',');
              final title = parts.isNotEmpty ? parts[0].trim() : displayName;
              final subtitle = parts.length > 1
                  ? parts.sublist(1, math.min(5, parts.length)).join(',').trim()
                  : displayName;
              final lat = double.tryParse(map['lat']?.toString() ?? '');
              final lon = double.tryParse(map['lon']?.toString() ?? '');

              if (lat != null && lon != null) {
                // Extract district/taluk to make location crystal clear
                final addressMap = map['address'] as Map<String, dynamic>?;
                final district = addressMap?['state_district'] ?? addressMap?['county'] ?? '';
                final state = addressMap?['state'] ?? 'India';
                final refinedTitle = district.toString().isNotEmpty && !title.toLowerCase().contains(district.toString().toLowerCase())
                    ? '$title ($district)'
                    : title;

                apiResults.add(
                  PlaceResult(
                    name: refinedTitle,
                    address: subtitle.isNotEmpty ? subtitle : '$district, $state',
                    latitude: lat,
                    longitude: lon,
                    category: _formatCategory(map['type']?.toString(), map['addresstype']?.toString()),
                  ),
                );
              }
            }
          }
        } catch (_) {
          // Network timeout or offline, gracefully continue
        }
      }),
    );

    // Merge offline matches + live API results without duplicate coordinates
    final allResults = <PlaceResult>[...localMatches];
    final seenCoords = localMatches.map((e) => '${e.latitude.toStringAsFixed(3)},${e.longitude.toStringAsFixed(3)}').toSet();

    for (final r in apiResults) {
      final key = '${r.latitude.toStringAsFixed(3)},${r.longitude.toStringAsFixed(3)}';
      if (!seenCoords.contains(key)) {
        seenCoords.add(key);
        allResults.add(r);
      }
    }

    return allResults;
  }

  static String _formatCategory(String? type, String? addressType) {
    final raw = (addressType ?? type ?? 'location').toLowerCase();
    switch (raw) {
      case 'village':
        return 'Village / Rural';
      case 'town':
        return 'Town';
      case 'city':
        return 'City';
      case 'suburb':
      case 'neighbourhood':
        return 'Locality';
      case 'aerodrome':
      case 'airport':
        return 'Airport';
      case 'station':
      case 'railway_station':
        return 'Railway Station';
      case 'bus_stop':
        return 'Bus Stop / Transit';
      default:
        return raw.substring(0, 1).toUpperCase() + raw.substring(1);
    }
  }
}
