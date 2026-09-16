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

  // Curated prominent Karnataka & All-India destinations for instant 0ms offline search
  static const List<PlaceResult> popularIndianPlaces = [
    PlaceResult(
      name: 'Gavanahalli',
      address: 'Chikkamagaluru taluku, Karnataka, 577142',
      latitude: 13.2919,
      longitude: 75.7558,
      category: 'Hometown / Village',
    ),
    PlaceResult(
      name: 'Devanahalli',
      address: 'Bengaluru North / Rural, Karnataka',
      latitude: 13.2483,
      longitude: 77.7126,
      category: 'Historic Town',
    ),
    PlaceResult(
      name: 'Chikkamagaluru Town',
      address: 'Chikkamagaluru District, Karnataka',
      latitude: 13.3161,
      longitude: 75.7720,
      category: 'Coffee Land / Hill Station',
    ),
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
      name: 'Mysuru Palace',
      address: 'Sayyaji Rao Road, Mysuru, Karnataka',
      latitude: 12.3051,
      longitude: 76.6551,
      category: 'Heritage Hub',
    ),
    PlaceResult(
      name: 'Mangaluru Coastal Port',
      address: 'Dakshina Kannada, Karnataka',
      latitude: 12.9141,
      longitude: 74.8560,
      category: 'Coastal Port City',
    ),
    PlaceResult(
      name: 'Hubballi - Dharwad',
      address: 'Hubballi Junction, North Karnataka',
      latitude: 15.3647,
      longitude: 75.1240,
      category: 'Commercial Hub',
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
    PlaceResult(
      name: 'Marina Beach',
      address: 'Kamarajar Salai, Chennai, Tamil Nadu',
      latitude: 13.0500,
      longitude: 80.2824,
      category: 'Coastal City',
    ),
  ];

  // Backward compatibility alias
  static List<PlaceResult> get popularBangalorePlaces => popularIndianPlaces;

  // Common spelling typos / phonetic normalizations
  static const Map<String, String> _aliases = {
    'gaveanhhili': 'gavanahalli',
    'gaveanhalli': 'gavanahalli',
    'gavanahilli': 'gavanahalli',
    'gavanahaly': 'gavanahalli',
    'gavanhalli': 'gavanahalli',
    'devanhalli': 'devanahalli',
    'devanahilli': 'devanahalli',
    'chikmagalur': 'chikkamagaluru',
    'chikmagalur town': 'chikkamagaluru',
    'chickmagalur': 'chikkamagaluru',
    'blr': 'kempegowda international airport',
    'airport': 'kempegowda international airport',
    'itpl': 'whitefield',
    'ecity': 'electronic city',
    'cp': 'connaught place',
  };

  /// Search places matching query across ALL OF INDIA via local instant index + OpenStreetMap live lookup
  Future<List<PlaceResult>> searchPlaces(String query) async {
    var clean = query.trim().toLowerCase();
    if (clean.isEmpty) return popularIndianPlaces;

    // Check alias normalization (handles user typos like "gaveanhhili" -> "gavanahalli")
    final normalized = _aliases[clean] ?? clean;

    // 1. First search local offline database
    final localMatches = popularIndianPlaces.where((p) {
      final n = p.name.toLowerCase();
      final a = p.address.toLowerCase();
      final c = p.category.toLowerCase();
      return n.contains(clean) ||
          a.contains(clean) ||
          c.contains(clean) ||
          n.contains(normalized) ||
          a.contains(normalized);
    }).toList();

    // 2. Query OpenStreetMap Nominatim across ALL OF INDIA
    try {
      final effectiveQuery = normalized;
      final encoded = Uri.encodeComponent(effectiveQuery);
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=$encoded&format=json&addressdetails=1&limit=8&countrycodes=in',
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
          final subtitle = parts.length > 1
              ? parts.sublist(1, math.min(5, parts.length)).join(',').trim()
              : displayName;
          final lat = double.tryParse(map['lat']?.toString() ?? '');
          final lon = double.tryParse(map['lon']?.toString() ?? '');

          if (lat != null && lon != null) {
            apiResults.add(
              PlaceResult(
                name: title,
                address: subtitle,
                latitude: lat,
                longitude: lon,
                category: _formatCategory(map['type']?.toString(), map['addresstype']?.toString()),
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

  static String _formatCategory(String? type, String? addressType) {
    final raw = (addressType ?? type ?? 'location').toLowerCase();
    switch (raw) {
      case 'village':
        return 'Village / Hometown';
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
      default:
        return raw.substring(0, 1).toUpperCase() + raw.substring(1);
    }
  }
}
