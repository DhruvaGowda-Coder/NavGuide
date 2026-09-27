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

  // Search suggestions are resolved through live providers; no developer-only
  // destination records are injected into the user's result list.
  static const List<PlaceResult> popularIndianPlaces = <PlaceResult>[];

  // Backward compatibility alias
  static List<PlaceResult> get popularBangalorePlaces => popularIndianPlaces;

  /// Generates spelling and district variants for search queries
  List<String> _expandQueryVariants(String query) {
    final clean = query.trim().toLowerCase();
    final normalized = clean
        .replaceAll(RegExp(r'\bssai\b'), 'sai')
        .replaceAll('ksuhi', 'kushi')
        .replaceAll('ksuh', 'kush')
        .replaceAll('aprtemnt', 'apartment')
        .replaceAll('aprtment', 'apartment')
        .replaceAll('apartmnt', 'apartment')
        .replaceAll(RegExp(r'\bahsan\b'), 'hassan')
        .replaceAll(RegExp(r'\bhasan\b'), 'hassan');
    final variants = <String>[clean, normalized];

    // Common vehicle-business wording should query the full intent before
    // falling back to broad single-token searches such as "motors".
    if (normalized.contains('durga') && normalized.contains('motor')) {
      variants.add('durga motors hassan');
      variants.add('ashok leyland durga hassan');
    }

    // Handles user phonetic variations for Gavenahalli / Gavanahalli
    if (clean.contains('gaven') ||
        clean.contains('gavan') ||
        clean.contains('gavean')) {
      variants.add('gavenahalli');
      variants.add('gavenahalli hassan');
      variants.add('gavanahalli');
      variants.add('gavanahalli chikkamagaluru');
    }

    // Handles Chaitanya / Nilaya / Nilayam apartment/house variations
    if (clean.contains('chait') ||
        clean.contains('chatny') ||
        clean.contains('chatan')) {
      variants.add('chaitanya');
      variants.add('chaitanya nilaya');
      variants.add('chaitanya nilayam');
    }
    if (clean.contains('nilay') ||
        clean.contains('nilya') ||
        clean.contains('nilyam')) {
      variants.add('nilayam');
      variants.add('nilaya');
    }

    // Handles Sai Kushi / Khushi apartment variations
    if (clean.contains('sai') &&
        (clean.contains('kush') ||
            clean.contains('ksuh') ||
            clean.contains('ksuhi') ||
            clean.contains('khush') ||
            normalized.contains('kush'))) {
      variants.add('sai kushi apartment');
      variants.add('sai khushi apartment');
      variants.add('sai kushi');
      variants.add('sai khushi');
      variants.add('sai apartment');
    }

    if (clean.contains('aprtment') ||
        clean.contains('aprtemnt') ||
        clean.contains('arpetment') ||
        clean.contains('apartmnt')) {
      variants.add(normalized);
      variants.add('apartment');
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

    if (clean.contains('station') ||
        clean.contains('train') ||
        clean.contains('rly')) {
      variants.add('railway station');
    }

    if (clean.contains('food') ||
        clean.contains('hotel') ||
        clean.contains('eat') ||
        clean.contains('rest')) {
      variants.add('restaurant');
    }

    // Add meaningful multi-word tokens
    final tokens = normalized
        .split(' ')
        .where((w) => w.trim().length >= 4)
        .toList();
    for (final t in tokens) {
      variants.add(t);
    }

    return variants.toSet().toList();
  }

  static const String googlePlacesApiKey = String.fromEnvironment(
    'GOOGLE_PLACES_API_KEY',
    defaultValue: 'AIzaSyCFkg5ywh9TX0lGglxsVeR6K8JF-BFC7Zc',
  );
  static const String _androidPackageName = 'com.navguardian.navguardian_ai';
  static const String _androidSigningSha1 =
      '766FBBD30674AF36140CFA6FD8BEBD81DE0722F6';

  /// Search places matching query across Google Places API (New) + OpenStreetMap Nominatim + Photon APIs
  Future<List<PlaceResult>> searchPlaces(
    String query, {
    double? userLat,
    double? userLon,
  }) async {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return const [];

    final variants = _expandQueryVariants(query);

    // Query Google Places API (New) + OpenStreetMap Nominatim + Photon across ALL OF INDIA.
    final googleResults = <PlaceResult>[];
    final apiResults = <PlaceResult>[];
    final queriedUrls = <String>{};

    final List<Future<void>> searchTasks = [];

    // We query primary variants concurrently across both Nominatim & Photon
    final queriesToRun = variants.take(4).toList();

    // --- Task 0: Google Places API (New) Text Search ---
    // Try corrected variants too, so typos like "ssai ksuhi aprtemnt" can still
    // hit the high-quality Google index once the key is allowed.
    for (final v in queriesToRun) {
      searchTasks.add(() async {
        final g = await _searchGooglePlaces(
          v,
          userLat: userLat,
          userLon: userLon,
        );
        googleResults.addAll(g);
      }());
    }

    // --- Task A: OpenStreetMap Nominatim ---
    for (final v in queriesToRun) {
      searchTasks.add(() async {
        final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(v)}&format=json&addressdetails=1&limit=8&countrycodes=in',
        );

        if (queriedUrls.contains(uri.toString())) return;
        queriedUrls.add(uri.toString());

        try {
          final req = await _client
              .getUrl(uri)
              .timeout(const Duration(seconds: 4));
          req.headers.set(
            'User-Agent',
            'NavGuardianAI-FlutterApp/1.0 (navguardian.ai)',
          );
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
                final addressMap = map['address'] as Map<String, dynamic>?;
                final district =
                    addressMap?['state_district'] ??
                    addressMap?['county'] ??
                    '';
                final state = addressMap?['state'] ?? 'India';
                final refinedTitle =
                    district.toString().isNotEmpty &&
                        !title.toLowerCase().contains(
                          district.toString().toLowerCase(),
                        )
                    ? '$title ($district)'
                    : title;

                apiResults.add(
                  PlaceResult(
                    name: refinedTitle,
                    address: subtitle.isNotEmpty
                        ? subtitle
                        : '$district, $state',
                    latitude: lat,
                    longitude: lon,
                    category: _formatCategory(
                      map['type']?.toString(),
                      map['addresstype']?.toString(),
                      name: refinedTitle,
                      address: subtitle,
                    ),
                  ),
                );
              }
            }
          }
        } catch (_) {}
      }());
    }

    // --- Task B: Photon OSM Search (Excels at addresses, house numbers, colonies, apartments) ---
    for (final v in queriesToRun) {
      searchTasks.add(() async {
        final photonUri = Uri.https('photon.komoot.io', '/api/', {
          'q': v,
          'limit': '10',
          if (userLat != null && userLon != null) ...{
            'lat': userLat.toString(),
            'lon': userLon.toString(),
          },
        });

        if (queriedUrls.contains(photonUri.toString())) return;
        queriedUrls.add(photonUri.toString());

        try {
          final req = await _client
              .getUrl(photonUri)
              .timeout(const Duration(seconds: 3));
          req.headers.set(HttpHeaders.userAgentHeader, 'NavGuardianApp/1.0');
          final res = await req.close().timeout(const Duration(seconds: 3));

          if (res.statusCode == 200) {
            final body = await res.transform(utf8.decoder).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            final features = json['features'] as List<dynamic>? ?? [];

            for (final f in features) {
              final props = f['properties'] as Map<String, dynamic>? ?? {};
              final country = props['country']?.toString().toLowerCase() ?? '';
              final countryCode =
                  props['countrycode']?.toString().toUpperCase() ?? '';

              // Filter for India
              if (country.isNotEmpty &&
                  country != 'india' &&
                  countryCode != 'IN') {
                continue;
              }

              final geom = f['geometry'] as Map<String, dynamic>? ?? {};
              final coords = geom['coordinates'] as List<dynamic>?;
              if (coords == null || coords.length < 2) continue;

              final pLon = (coords[0] as num).toDouble();
              final pLat = (coords[1] as num).toDouble();

              final rawName =
                  (props['name'] as String?)?.trim() ??
                  (props['street'] as String?)?.trim() ??
                  v;
              if (rawName.isEmpty) continue;

              final houseNumber = props['housenumber'] as String? ?? '';
              final street = props['street'] as String? ?? '';
              final locality =
                  props['district'] as String? ??
                  props['suburb'] as String? ??
                  '';
              final city = props['city'] as String? ?? '';
              final state = props['state'] as String? ?? '';
              final postcode = props['postcode'] as String? ?? '';

              final addrParts = [
                if (houseNumber.isNotEmpty) '#$houseNumber',
                if (street.isNotEmpty && street != rawName) street,
                if (locality.isNotEmpty && locality != rawName) locality,
                if (city.isNotEmpty) city,
                if (state.isNotEmpty) state,
                if (postcode.isNotEmpty) postcode,
              ];

              final address = addrParts.isNotEmpty
                  ? addrParts.join(', ')
                  : 'India';
              final category = _formatCategory(
                props['osm_value']?.toString(),
                props['type']?.toString(),
                name: rawName,
                address: address,
              );

              apiResults.add(
                PlaceResult(
                  name: houseNumber.isNotEmpty && !rawName.contains('#')
                      ? '$rawName ($houseNumber)'
                      : rawName,
                  address: address,
                  latitude: pLat,
                  longitude: pLon,
                  category: category,
                ),
              );
            }
          }
        } catch (_) {}
      }());
    }

    await Future.wait(searchTasks);

    // Merge live providers. No developer-only destination records are injected.
    final allResults = <PlaceResult>[];
    final seenCoords = <String>{};

    for (final r in googleResults) {
      final key =
          '${r.latitude.toStringAsFixed(3)},${r.longitude.toStringAsFixed(3)}';
      if (!seenCoords.contains(key)) {
        seenCoords.add(key);
        allResults.add(r);
      }
    }

    for (final r in apiResults) {
      final key =
          '${r.latitude.toStringAsFixed(3)},${r.longitude.toStringAsFixed(3)}';
      if (!seenCoords.contains(key)) {
        seenCoords.add(key);
        allResults.add(r);
      }
    }

    if (allResults.length > 1) {
      final searchTokens = _searchTokens(query);
      final relevantResults = allResults
          .where((place) => _searchRelevance(place, searchTokens) > 0)
          .toList();

      // Named searches must show matching businesses first. This prevents a
      // generic nearby "Motors" result from outranking the requested brand.
      final rankedResults = relevantResults.isNotEmpty
          ? relevantResults
          : allResults;
      rankedResults.sort((a, b) {
        final scoreA = _searchRelevance(a, searchTokens);
        final scoreB = _searchRelevance(b, searchTokens);
        if (scoreA != scoreB) return scoreB.compareTo(scoreA);

        if (userLat != null && userLon != null) {
          final distA = _distanceSquared(a, userLat, userLon);
          final distB = _distanceSquared(b, userLat, userLon);
          return distA.compareTo(distB);
        }
        return 0;
      });

      return rankedResults;
    }

    return allResults;
  }

  List<String> _searchTokens(String query) {
    final normalized = query
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\bahsan\b'), 'hassan')
        .replaceAll(RegExp(r'\bhasan\b'), 'hassan');
    return normalized
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.length >= 3)
        .toSet()
        .toList();
  }

  int _searchRelevance(PlaceResult place, List<String> tokens) {
    if (tokens.isEmpty) return 0;
    final name = place.name.toLowerCase();
    final haystack = '${place.name} ${place.address} ${place.category}'
        .toLowerCase();
    final matchedTokens = tokens.where(haystack.contains).length;
    final matchedNameTokens = tokens.where(name.contains).length;
    var score = matchedTokens * 10 + matchedNameTokens * 20;
    if (name.contains(tokens.first)) score += 60;
    if (tokens.length > 1 && matchedTokens == tokens.length) score += 100;
    if (tokens.length > 1 && matchedNameTokens == tokens.length) score += 100;
    return score;
  }

  double _distanceSquared(PlaceResult place, double lat, double lon) {
    final latDelta = place.latitude - lat;
    final lonDelta = place.longitude - lon;
    return latDelta * latDelta + lonDelta * lonDelta;
  }

  /// Queries Google Places API (New) Text Search for hyper-accurate, house & apartment level POIs
  Future<List<PlaceResult>> _searchGooglePlaces(
    String query, {
    double? userLat,
    double? userLon,
  }) async {
    if (googlePlacesApiKey.isEmpty) return [];
    try {
      final uri = Uri.parse(
        'https://places.googleapis.com/v1/places:searchText',
      );
      final req = await _client
          .postUrl(uri)
          .timeout(const Duration(seconds: 4));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.headers.set('X-Goog-Api-Key', googlePlacesApiKey);
      req.headers.set('X-Android-Package', _androidPackageName);
      req.headers.set('X-Android-Cert', _androidSigningSha1);
      req.headers.set(
        'X-Goog-FieldMask',
        'places.displayName,places.formattedAddress,places.location,places.types',
      );

      final bodyMap = <String, dynamic>{'textQuery': query};
      if (userLat != null && userLon != null) {
        bodyMap['locationBias'] = {
          'circle': {
            'center': {'latitude': userLat, 'longitude': userLon},
            'radius': 50000.0,
          },
        };
      }
      req.write(jsonEncode(bodyMap));
      final res = await req.close().timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final places = data['places'] as List<dynamic>? ?? [];
        final list = <PlaceResult>[];
        for (final item in places) {
          final m = item as Map<String, dynamic>;
          final name = m['displayName']?['text']?.toString().trim() ?? '';
          final address = m['formattedAddress']?.toString().trim() ?? '';
          final loc = m['location'] as Map<String, dynamic>?;
          final lat = (loc?['latitude'] as num?)?.toDouble();
          final lon = (loc?['longitude'] as num?)?.toDouble();
          if (name.isNotEmpty && lat != null && lon != null) {
            final types =
                (m['types'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [];
            list.add(
              PlaceResult(
                name: name,
                address: address,
                latitude: lat,
                longitude: lon,
                category: _formatGoogleCategory(
                  types,
                  name: name,
                  address: address,
                ),
              ),
            );
          }
        }
        return list;
      }
    } catch (_) {}
    return [];
  }

  static String _formatGoogleCategory(
    List<String> types, {
    String name = '',
    String address = '',
  }) {
    final placeText = '$name $address'.toLowerCase();
    if (_looksLikeVehicleBusiness(placeText)) {
      return 'Vehicle Showroom / Workshop';
    }
    if (types.contains('apartment_building') ||
        types.contains('housing_complex') ||
        types.contains('residential')) {
      return 'Apartment / Society';
    }
    if (types.contains('restaurant') ||
        types.contains('cafe') ||
        types.contains('food') ||
        types.contains('meal_takeaway')) {
      return 'Restaurant / Dining';
    }
    if (types.contains('gas_station')) return 'Fuel / Petrol Pump';
    if (types.contains('car_dealer') ||
        types.contains('motorcycle_dealer') ||
        types.contains('car_repair') ||
        types.contains('auto_repair') ||
        types.contains('auto_parts_store')) {
      return 'Vehicle Showroom / Workshop';
    }
    if (types.contains('hospital') ||
        types.contains('pharmacy') ||
        types.contains('doctor'))
      return 'Hospital / Medical';
    if (types.contains('lodging') || types.contains('hotel'))
      return 'Hotel / Stay';
    if (types.contains('place_of_worship') || types.contains('hindu_temple'))
      return 'Heritage / Temple';
    if (types.contains('shopping_mall') ||
        types.contains('store') ||
        types.contains('supermarket'))
      return 'Shopping / Mall';
    if (types.contains('transit_station') ||
        types.contains('train_station') ||
        types.contains('bus_station'))
      return 'Transit Station';
    return 'Google Verified Location';
  }

  static String _formatCategory(
    String? type,
    String? addressType, {
    String name = '',
    String address = '',
  }) {
    final raw = (addressType ?? type ?? 'location').toLowerCase();
    final placeText = '$name $address $raw'.toLowerCase();
    if (_looksLikeVehicleBusiness(placeText)) {
      return 'Vehicle Showroom / Workshop';
    }
    switch (raw) {
      case 'restaurant':
      case 'food_court':
      case 'fast_food':
        return 'Restaurant / Dining';
      case 'cafe':
        return 'Cafe / Coffee';
      case 'hotel':
      case 'motel':
      case 'guest_house':
      case 'hostel':
        return 'Hotel / Stay';
      case 'station':
      case 'railway_station':
      case 'halt':
        return 'Railway Station';
      case 'bus_stop':
      case 'bus_station':
        return 'Bus Terminal';
      case 'airport':
      case 'aerodrome':
        return 'Airport';
      case 'hospital':
      case 'clinic':
      case 'pharmacy':
        return 'Hospital / Health';
      case 'fuel':
      case 'gas_station':
        return 'Fuel / Petrol Bunk';
      case 'bank':
      case 'atm':
        return 'ATM / Bank';
      case 'place_of_worship':
      case 'temple':
      case 'church':
      case 'mosque':
        return 'Heritage / Temple';
      case 'attraction':
      case 'tourism':
      case 'viewpoint':
      case 'museum':
        return 'Tourist Attraction';
      case 'village':
        return 'Village / Rural';
      case 'town':
        return 'Town';
      case 'city':
        return 'City';
      case 'suburb':
      case 'neighbourhood':
        return 'Locality';
      default:
        return raw.length > 1
            ? raw.substring(0, 1).toUpperCase() + raw.substring(1)
            : raw;
    }
  }

  static bool _looksLikeVehicleBusiness(String text) {
    final vehicleTerms = [
      'ashok leyland',
      'tvs ',
      'hero motocorp',
      'royal enfield',
      'bajaj auto',
      'mahindra',
      'tata motors',
      'honda ',
      'yamaha ',
      'suzuki ',
      'ather ',
      'ola electric',
      'motor',
      'motors',
      'automobile',
      'vehicle showroom',
      'showroom',
      'workshop',
      'service center',
      'service centre',
      'auto repair',
      'car dealer',
      'bike dealer',
      'two wheeler',
      'four wheeler',
      'tyre',
      'tyres',
    ];
    return vehicleTerms.any(text.contains);
  }
}
