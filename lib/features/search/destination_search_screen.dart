import 'package:geolocator/geolocator.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../safety_data/route_safety_inspection_screen.dart';
import '../safety_scoring/route_safety_recommendation_screen.dart';
import '../location/location_controller.dart';
import '../../device/search/place_search_service.dart';

class DestinationSearchScreen extends ConsumerStatefulWidget {
  const DestinationSearchScreen({super.key});

  @override
  ConsumerState<DestinationSearchScreen> createState() =>
      _DestinationSearchScreenState();
}

class _DestinationSearchScreenState
    extends ConsumerState<DestinationSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final PlaceSearchService _placeSearchService = PlaceSearchService();
  Timer? _debounceTimer;

  String _query = '';
  bool _isSearchingLive = false;
  double? _detectedLat;
  double? _detectedLon;
  List<PlaceResult> _placeSuggestions = [];

  final List<String> _quickChips = [
    'Hassan Jn (HAS)',
    'KSR Bengaluru (SBC)',
    'Sakleshpur',
    'Chikkamagaluru',
    'Paakashala',
    'Kamat Lokaruchi',
    'Swathi Delicacy',
    'Airport (BLR)',
    'Mysuru Palace',
    'Gavenahalli (Hassan)',
    'Indiranagar',
  ];

  (IconData, Color) _getCategoryVisuals(String category) {
    final cat = category.toLowerCase();
    if (cat.contains('train') ||
        cat.contains('railway') ||
        cat.contains('station')) {
      return (Icons.train_rounded, const Color(0xff1565C0));
    } else if (cat.contains('restaurant') ||
        cat.contains('dining') ||
        cat.contains('food')) {
      return (Icons.restaurant_rounded, const Color(0xffD84315));
    } else if (cat.contains('cafe') || cat.contains('coffee')) {
      return (Icons.local_cafe_rounded, const Color(0xff6D4C41));
    } else if (cat.contains('hotel') ||
        cat.contains('stay') ||
        cat.contains('lodge')) {
      return (Icons.hotel_rounded, const Color(0xff5E35B1));
    } else if (cat.contains('hospital') ||
        cat.contains('health') ||
        cat.contains('clinic')) {
      return (Icons.local_hospital_rounded, const Color(0xffC62828));
    } else if (cat.contains('fuel') || cat.contains('petrol')) {
      return (Icons.local_gas_station_rounded, const Color(0xff00838F));
    } else if (cat.contains('vehicle') ||
        cat.contains('showroom') ||
        cat.contains('workshop') ||
        cat.contains('motor')) {
      return (Icons.directions_car_filled_rounded, const Color(0xff6A1B9A));
    } else if (cat.contains('heritage') ||
        cat.contains('temple') ||
        cat.contains('tourist')) {
      return (Icons.account_balance_rounded, const Color(0xffE65100));
    } else if (cat.contains('airport')) {
      return (Icons.flight_takeoff_rounded, const Color(0xff0277BD));
    }
    return (Icons.location_on_rounded, const Color(0xff23695a));
  }

  @override
  void initState() {
    super.initState();
    _placeSuggestions = const [];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(locationControllerProvider.notifier).start();
      _detectCurrentLocation();
    });
  }

  Future<void> _detectCurrentLocation() async {
    try {
      final pos =
          await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 3),
            ),
          );
      if (mounted) {
        setState(() {
          _detectedLat = pos.latitude;
          _detectedLon = pos.longitude;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String val) {
    setState(() {
      _query = val.trim();
    });

    _debounceTimer?.cancel();
    if (_query.isEmpty) {
      setState(() {
        _placeSuggestions = const [];
        _isSearchingLive = false;
      });
      return;
    }

    setState(() {
      _placeSuggestions = const [];
      _isSearchingLive = true;
    });

    // Debounced live network query
    _debounceTimer = Timer(const Duration(milliseconds: 200), () async {
      final currentQuery = _query;
      final results = await _placeSearchService.searchPlaces(
        currentQuery,
        userLat: _detectedLat,
        userLon: _detectedLon,
      );
      if (!mounted || _query != currentQuery) return;
      setState(() {
        _placeSuggestions = results;
        _isSearchingLive = false;
      });
    });
  }

  Future<void> _navigateToDestination(PlaceResult place) async {
    final fix = ref.read(locationControllerProvider).fix;
    double currentLat = fix?.latitude ?? _detectedLat ?? 12.9716;
    double currentLon = fix?.longitude ?? _detectedLon ?? 77.5946;
    String originName = (fix != null || _detectedLat != null)
        ? 'Current Location'
        : 'Bengaluru Center';

    if (fix == null && _detectedLat == null) {
      try {
        final pos = await Geolocator.getLastKnownPosition().timeout(
          const Duration(milliseconds: 400),
          onTimeout: () => null,
        );
        if (pos != null) {
          currentLat = pos.latitude;
          currentLon = pos.longitude;
          originName = 'Current Location';
        }
      } catch (_) {}
    }

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RouteSafetyRecommendationScreen(
          customOriginLat: currentLat,
          customOriginLon: currentLon,
          customOriginName: originName,
          customDestLat: place.latitude,
          customDestLon: place.longitude,
          customDestName: place.name,
        ),
      ),
    );
  }

  double _calcDistanceKm(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a =
        0.5 -
        math.cos((lat2 - lat1) * p) / 2 +
        math.cos(lat1 * p) *
            math.cos(lat2 * p) *
            (1 - math.cos((lon2 - lon1) * p)) /
            2;
    return 12742 * math.asin(math.sqrt(a));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final fix = ref.read(locationControllerProvider).fix;
    final userLat = fix?.latitude ?? _detectedLat;
    final userLon = fix?.longitude ?? _detectedLon;

    return Scaffold(
      appBar: AppBar(title: const Text('Destination Search & Routes')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomInset),
        children: [
          // Search Input Bar
          TextField(
            controller: _searchController,
            onChanged: _onQueryChanged,
            decoration: InputDecoration(
              labelText: 'Where would you like to go?',
              hintText: 'Search any town, village, or city in India (e.g. Gavanahalli)…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _isSearchingLive
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (_query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _onQueryChanged('');
                            },
                          )
                        : null),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),
          const SizedBox(height: 12),

          // Quick Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ActionChip(
                  label: const Text(
                    'All Places',
                    style: TextStyle(fontSize: 11),
                  ),
                  avatar: const Icon(Icons.location_on_outlined, size: 14),
                  onPressed: () {
                    _searchController.clear();
                    _onQueryChanged('');
                  },
                ),
                const SizedBox(width: 6),
                for (final chip in _quickChips)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      label: Text(chip, style: const TextStyle(fontSize: 11)),
                      onPressed: () {
                        _searchController.text = chip;
                        _onQueryChanged(chip);
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Consumer-Facing AI Safest-Route Recommendation Banner (No Phase badges)
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xff23695a), width: 1.5),
            ),
            color: const Color(0xff23695a).withValues(alpha: 0.06),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xff23695a),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.shield,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Safest-Route AI Engine',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xff23695a),
                              ),
                            ),
                            Text(
                              'Live Risk Evaluation · Accident & Flood Hotspots',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Evaluates candidate routes balancing safety vs. travel time. Identifies critical flood zones, accident blackspots, and weather hazards along your path.',
                    style: TextStyle(fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xff23695a).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.touch_app_outlined,
                          size: 16,
                          color: Color(0xff23695a),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Tap any destination below or search above to start',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xff23695a),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Dynamic Place Results Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _query.isEmpty
                    ? 'Search Destinations'
                    : 'Matching Destinations in India',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isSearchingLive) ...[
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xff23695a),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    '${_placeSuggestions.length} found',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_isSearchingLive && _placeSuggestions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Column(
                  children: [
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Color(0xff23695a),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Searching houses, apartments & landmarks across India...',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_placeSuggestions.isEmpty && _query.isEmpty)
            Card(
              elevation: 0,
              color: Colors.grey.shade100,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.explore_outlined,
                      size: 40,
                      color: Color(0xff23695a),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Search live destinations',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Choose a popular search shortcut above or type any place name.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          else if (_placeSuggestions.isEmpty)
            Card(
              elevation: 0,
              color: Colors.grey.shade100,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 40,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No destinations found for "$_query"',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Try searching by apartment name, colony, landmark, or city (e.g. Chaitanya Nilaya, Sai Kushi, Hassan, Bengaluru).',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        _searchController.clear();
                        _onQueryChanged('');
                      },
                      child: const Text('Clear Search'),
                    ),
                  ],
                ),
              ),
            )
          else
            for (final place in _placeSuggestions) ...[
              Builder(
                builder: (context) {
                  final (catIcon, catColor) = _getCategoryVisuals(
                    place.category,
                  );
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: catColor.withValues(alpha: 0.12),
                        child: Icon(catIcon, color: catColor, size: 20),
                      ),
                      title: Text(
                        place.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        place.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: catColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: catColor.withValues(alpha: 0.25),
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              place.category,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: catColor,
                              ),
                            ),
                          ),
                          if (userLat != null && userLon != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${_calcDistanceKm(userLat, userLon, place.latitude, place.longitude).toStringAsFixed(1)} km',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ],
                      ),
                      onTap: () => _navigateToDestination(place),
                    ),
                  );
                },
              ),
            ],

          const SizedBox(height: 24),

          // Standard Pre-Monitored Safety Corridors
          Text(
            'Pre-Monitored High-Risk Corridors',
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < kBangaloreRoutePresets.length; i++) ...[
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.teal.shade50,
                  child: Icon(Icons.route, color: Colors.teal.shade800),
                ),
                title: Text(
                  kBangaloreRoutePresets[i].title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  kBangaloreRoutePresets[i].subtitle,
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: Colors.grey,
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RouteSafetyRecommendationScreen(
                        initialPresetIndex: i,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
