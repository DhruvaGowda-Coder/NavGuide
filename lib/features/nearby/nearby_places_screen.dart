import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../safety_scoring/route_safety_recommendation_screen.dart';
import 'nearby_places_service.dart';

class NearbyPlacesScreen extends StatefulWidget {
  final PlaceCategory? initialCategory;

  const NearbyPlacesScreen({super.key, this.initialCategory});

  @override
  State<NearbyPlacesScreen> createState() => _NearbyPlacesScreenState();
}

class _NearbyPlacesScreenState extends State<NearbyPlacesScreen> {
  final NearbyPlacesService _service = NearbyPlacesService();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchDebounce;

  GoogleMapController? _mapController;
  LatLng _userPosition = const LatLng(
    12.9716,
    77.5946,
  ); // Default Bangalore fallback
  bool _isLoadingPlaces = false;
  int _fetchGeneration = 0;
  PlaceCategory? _selectedCategory;
  double _radiusKm = 5.0;
  List<NearbyPlace> _places = [];
  NearbyPlace? _selectedPlace;
  bool _isMapViewExpanded = false;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
    _searchFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
    _applyInstantPlaces();
    _initUserGpsAndFetch();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initUserGpsAndFetch() async {
    if (mounted) {
      setState(() => _isLoadingPlaces = true);
    }
    try {
      final lastKnown = await Geolocator.getLastKnownPosition().timeout(
        const Duration(milliseconds: 700),
        onTimeout: () => null,
      );
      if (lastKnown != null &&
          lastKnown.latitude != 0 &&
          lastKnown.longitude != 0) {
        _userPosition = LatLng(lastKnown.latitude, lastKnown.longitude);
        await _fetchPlaces();
      }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always) {
        final pos =
            await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.medium,
              ),
            ).timeout(
              const Duration(seconds: 2),
              onTimeout: () async {
                return await Geolocator.getLastKnownPosition() ??
                    Position(
                      longitude: 77.5946,
                      latitude: 12.9716,
                      timestamp: DateTime.now(),
                      accuracy: 0,
                      altitude: 0,
                      altitudeAccuracy: 0,
                      heading: 0,
                      headingAccuracy: 0,
                      speed: 0,
                      speedAccuracy: 0,
                    );
              },
            );

        if (pos.latitude != 0 && pos.longitude != 0) {
          _userPosition = LatLng(pos.latitude, pos.longitude);
        }
      }
    } catch (_) {}

    await _fetchPlaces();
  }

  void _applyInstantPlaces() {
    final instantList = _service.getInstantPlaces(
      userLat: _userPosition.latitude,
      userLng: _userPosition.longitude,
      filterCategory: _selectedCategory,
      maxRadiusKm: _radiusKm,
      searchQuery: _searchCtrl.text,
    );

    if (instantList.isEmpty) return;
    _places = instantList;
    _selectedPlace ??= instantList.first;
  }

  Future<void> _fetchPlaces() async {
    final generation = ++_fetchGeneration;
    final searchQuery = _searchCtrl.text;
    final selectedCategory = _selectedCategory;
    final radiusKm = _radiusKm;

    // 1. Immediately display curated & cached places (0ms instant response!)
    final instantList = _service.getInstantPlaces(
      userLat: _userPosition.latitude,
      userLng: _userPosition.longitude,
      filterCategory: selectedCategory,
      maxRadiusKm: radiusKm,
      searchQuery: searchQuery,
    );

    if (!mounted || generation != _fetchGeneration) return;
    if (instantList.isNotEmpty) {
      setState(() {
        _places = instantList;
        _selectedPlace = instantList.first;
        _isLoadingPlaces = true;
      });
      if (!_searchFocusNode.hasFocus) {
        _fitMapToPlaces();
      }
    } else {
      setState(() {
        _places = [];
        _selectedPlace = null;
        _isLoadingPlaces = true;
      });
    }

    // 2. Fetch live updates/amenities smoothly in the background
    try {
      final results = await _service.getNearbyPlaces(
        userLat: _userPosition.latitude,
        userLng: _userPosition.longitude,
        filterCategory: selectedCategory,
        maxRadiusKm: radiusKm,
        searchQuery: searchQuery,
        forceRefresh: true,
      );

      if (mounted && generation == _fetchGeneration) {
        setState(() {
          _places = results;
          _selectedPlace = results.isEmpty ? null : results.first;
        });
        if (results.isNotEmpty && !_searchFocusNode.hasFocus) {
          _fitMapToPlaces();
        }
      }
    } catch (_) {
    } finally {
      if (mounted && generation == _fetchGeneration) {
        setState(() => _isLoadingPlaces = false);
      }
    }
  }

  void _fitMapToPlaces() {
    if (_mapController == null) return;
    // Do not animate camera if user is focused on the search input
    if (_searchFocusNode.hasFocus) return;

    double minLat = _userPosition.latitude;
    double maxLat = _userPosition.latitude;
    double minLng = _userPosition.longitude;
    double maxLng = _userPosition.longitude;

    for (final p in _places.take(15)) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }

    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - 0.04, minLng - 0.04),
          northeast: LatLng(maxLat + 0.04, maxLng + 0.04),
        ),
        55,
      ),
    );
  }

  void _centerOnPlace(NearbyPlace place) {
    setState(() => _selectedPlace = place);
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(place.latitude, place.longitude), 15.0),
    );
  }

  /// Opens NavGuardian native routing & live navigation directly to this place
  void _navigateToPlaceWithNavGuardian(NearbyPlace place) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RouteSafetyRecommendationScreen(
          customOriginLat: _userPosition.latitude,
          customOriginLon: _userPosition.longitude,
          customOriginName: 'My Location',
          customDestLat: place.latitude,
          customDestLon: place.longitude,
          customDestName: place.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Build markers for map
    final Set<Marker> markers = {};

    // 1. Live User Marker
    markers.add(
      Marker(
        markerId: const MarkerId('user_live_pos'),
        position: _userPosition,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
        infoWindow: const InfoWindow(
          title: 'You are here 📍',
          snippet: 'Current Live GPS',
        ),
        zIndexInt: 10,
      ),
    );

    // 2. Place Markers
    for (final p in _places) {
      final isSelected = _selectedPlace?.id == p.id;
      markers.add(
        Marker(
          markerId: MarkerId(p.id),
          position: LatLng(p.latitude, p.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(p.hueColor),
          infoWindow: InfoWindow(
            title: '${p.categoryEmoji} ${p.name}',
            snippet: '${p.formattedDistance} • Tap to Start Route 🧭',
            onTap: () => _navigateToPlaceWithNavGuardian(p),
          ),
          zIndexInt: isSelected ? 8 : 4,
          onTap: () {
            setState(() => _selectedPlace = p);
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6F3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.near_me_rounded,
                color: Color(0xFF23695A),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nearby Pit Stops & Hub',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E293B),
                  ),
                ),
                Text(
                  'Restaurants, Pumps, EV & Highway Services',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh Live Location',
            icon: _isLoadingPlaces
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF23695A),
                    ),
                  )
                : const Icon(Icons.refresh_rounded, color: Color(0xFF23695A)),
            onPressed: _initUserGpsAndFetch,
          ),
          IconButton(
            tooltip: _isMapViewExpanded ? 'Collapse Map' : 'Expand Map',
            icon: Icon(
              _isMapViewExpanded
                  ? Icons.view_agenda_outlined
                  : Icons.map_outlined,
              color: const Color(0xFF23695A),
            ),
            onPressed: () =>
                setState(() => _isMapViewExpanded = !_isMapViewExpanded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildSearchAndFilters(),
            SizedBox(
              height: _isMapViewExpanded
                  ? MediaQuery.of(context).size.height * 0.40
                  : 155,
              child: _buildMapWidget(markers),
            ),
            _buildPlacesHeader(),
            Expanded(child: _buildPlacesList()),
          ],
        ),
      ),
    );
  }

  /// Interactive Google Map with Range Selector and Recenter Floating Pills
  Widget _buildMapWidget(Set<Marker> markers) {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _userPosition,
            zoom: 12,
          ),
          markers: markers,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          buildingsEnabled: true,
          onMapCreated: (ctrl) {
            _mapController = ctrl;
            _fitMapToPlaces();
          },
        ),

        // Radius Range Overlay Pill (Big, High-Contrast & 100% Clickable)
        Positioned(
          left: 12,
          bottom: 12,
          child: PopupMenuButton<double>(
            tooltip: 'Select Search Radius',
            offset: const Offset(0, -230),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            onSelected: (val) {
              setState(() => _radiusKm = val);
              _fetchPlaces();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 5.0,
                child: Row(
                  children: [
                    Icon(
                      Icons.directions_walk_rounded,
                      size: 22,
                      color: _radiusKm == 5.0
                          ? const Color(0xFF23695A)
                          : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Within 5 km (Walking / City)',
                        style: TextStyle(
                          fontWeight: _radiusKm == 5.0
                              ? FontWeight.w900
                              : FontWeight.w600,
                          fontSize: 13.5,
                          color: _radiusKm == 5.0
                              ? const Color(0xFF23695A)
                              : const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    if (_radiusKm == 5.0)
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: Color(0xFF23695A),
                      ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 10.0,
                child: Row(
                  children: [
                    Icon(
                      Icons.location_city_rounded,
                      size: 22,
                      color: _radiusKm == 10.0
                          ? const Color(0xFF23695A)
                          : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Within 10 km (Suburbs)',
                        style: TextStyle(
                          fontWeight: _radiusKm == 10.0
                              ? FontWeight.w900
                              : FontWeight.w600,
                          fontSize: 13.5,
                          color: _radiusKm == 10.0
                              ? const Color(0xFF23695A)
                              : const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    if (_radiusKm == 10.0)
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: Color(0xFF23695A),
                      ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 25.0,
                child: Row(
                  children: [
                    Icon(
                      Icons.commute_rounded,
                      size: 22,
                      color: _radiusKm == 25.0
                          ? const Color(0xFF23695A)
                          : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Within 25 km (Metro Area)',
                        style: TextStyle(
                          fontWeight: _radiusKm == 25.0
                              ? FontWeight.w900
                              : FontWeight.w600,
                          fontSize: 13.5,
                          color: _radiusKm == 25.0
                              ? const Color(0xFF23695A)
                              : const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    if (_radiusKm == 25.0)
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: Color(0xFF23695A),
                      ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 50.0,
                child: Row(
                  children: [
                    Icon(
                      Icons.alt_route_rounded,
                      size: 22,
                      color: _radiusKm == 50.0
                          ? const Color(0xFF23695A)
                          : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Within 50 km (Highway Corridor)',
                        style: TextStyle(
                          fontWeight: _radiusKm == 50.0
                              ? FontWeight.w900
                              : FontWeight.w600,
                          fontSize: 13.5,
                          color: _radiusKm == 50.0
                              ? const Color(0xFF23695A)
                              : const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    if (_radiusKm == 50.0)
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: Color(0xFF23695A),
                      ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 100.0,
                child: Row(
                  children: [
                    Icon(
                      Icons.explore_rounded,
                      size: 22,
                      color: _radiusKm == 100.0
                          ? const Color(0xFF23695A)
                          : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Within 100 km (Intercity Travel)',
                        style: TextStyle(
                          fontWeight: _radiusKm == 100.0
                              ? FontWeight.w900
                              : FontWeight.w600,
                          fontSize: 13.5,
                          color: _radiusKm == 100.0
                              ? const Color(0xFF23695A)
                              : const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    if (_radiusKm == 100.0)
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: Color(0xFF23695A),
                      ),
                  ],
                ),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF23695A), width: 1.8),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF23695A).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.radar_rounded,
                      size: 18,
                      color: Color(0xFF23695A),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Within ${_radiusKm.toInt()} km',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF134E42),
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF23695A).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.arrow_drop_down_rounded,
                      size: 30,
                      color: Color(0xFF23695A),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Re-center on User Live GPS
        Positioned(
          right: 12,
          bottom: 12,
          child: FloatingActionButton.small(
            heroTag: 'nearby_gps_recenter',
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF23695A),
            elevation: 3,
            tooltip: 'Recenter on My Location',
            onPressed: () {
              _mapController?.animateCamera(
                CameraUpdate.newLatLngZoom(_userPosition, 14.0),
              );
            },
            child: const Icon(Icons.my_location_rounded, size: 18),
          ),
        ),
      ],
    );
  }

  /// Search Bar and Horizontal Category Chips
  Widget _buildSearchAndFilters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Live Search Input (Real-time Typing with Focus Protection)
          Container(
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _searchFocusNode.hasFocus
                    ? const Color(0xFF23695A)
                    : Colors.transparent,
                width: 1.2,
              ),
            ),
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocusNode,
              textInputAction: TextInputAction.search,
              onChanged: (val) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                  _fetchPlaces();
                });
              },
              onSubmitted: (_) {
                _searchDebounce?.cancel();
                _fetchPlaces();
              },
              decoration: InputDecoration(
                hintText: 'Search restaurants, ATMs, toilets, pharmacies, fuel, EV...',
                hintStyle: TextStyle(
                  fontSize: 12.5,
                  color: Colors.grey.shade500,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF23695A),
                  size: 20,
                ),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _searchCtrl,
                  builder: (context, val, _) {
                    if (val.text.isEmpty) return const SizedBox.shrink();
                    return IconButton(
                      icon: const Icon(
                        Icons.clear_rounded,
                        size: 18,
                        color: Colors.grey,
                      ),
                      onPressed: () {
                        _searchCtrl.clear();
                        _fetchPlaces();
                      },
                    );
                  },
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Category Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildCategoryChip(
                  null,
                  'All Stops',
                  Icons.apps_rounded,
                  const Color(0xFF23695A),
                ),
                const SizedBox(width: 6),
                _buildCategoryChip(
                  PlaceCategory.restaurant,
                  'Restaurants',
                  Icons.restaurant_rounded,
                  Colors.deepOrange,
                ),
                const SizedBox(width: 6),
                _buildCategoryChip(
                  PlaceCategory.fuel,
                  'Petrol Pumps',
                  Icons.local_gas_station_rounded,
                  Colors.blue,
                ),
                const SizedBox(width: 6),
                _buildCategoryChip(
                  PlaceCategory.atm,
                  'ATMs',
                  Icons.atm_rounded,
                  Colors.indigo,
                ),
                const SizedBox(width: 6),
                _buildCategoryChip(
                  PlaceCategory.toilet,
                  'Public Toilets',
                  Icons.wc_rounded,
                  Colors.teal,
                ),
                const SizedBox(width: 6),
                _buildCategoryChip(
                  PlaceCategory.pharmacy,
                  'Pharmacies',
                  Icons.local_pharmacy_rounded,
                  Colors.pink,
                ),
                const SizedBox(width: 6),
                _buildCategoryChip(
                  PlaceCategory.parking,
                  'Parking',
                  Icons.local_parking_rounded,
                  Colors.blue.shade700,
                ),
                const SizedBox(width: 6),
                _buildCategoryChip(
                  PlaceCategory.ev,
                  'EV Chargers',
                  Icons.ev_station_rounded,
                  Colors.green,
                ),
                const SizedBox(width: 6),
                _buildCategoryChip(
                  PlaceCategory.mechanic,
                  'Service & Garage',
                  Icons.build_rounded,
                  Colors.deepPurple,
                ),
                const SizedBox(width: 6),
                _buildCategoryChip(
                  PlaceCategory.tourist,
                  'Tourist Spots',
                  Icons.account_balance_rounded,
                  Colors.amber.shade800,
                ),
                const SizedBox(width: 6),
                _buildCategoryChip(
                  PlaceCategory.hospital,
                  'Emergency Medical',
                  Icons.local_hospital_rounded,
                  Colors.red,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Results count and Live Verified badge
  Widget _buildPlacesHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${_places.length} Places Found',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13,
              color: Color(0xFF334155),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6F3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 12,
                  color: Color(0xFF23695A),
                ),
                SizedBox(width: 4),
                Text(
                  'NavGuide Verified',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF23695A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// List of Places or Loading/Empty State
  Widget _buildPlacesList() {
    if (_isLoadingPlaces && _places.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF23695A)),
            SizedBox(height: 12),
            Text(
              'Finding nearby amenities...',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    if (_places.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.storefront_outlined,
                size: 48,
                color: Colors.grey,
              ),
              const SizedBox(height: 12),
              Text(
                _emptyPlacesTitle(),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Try increasing the search distance or picking another category.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _radiusKm = 50.0;
                    _selectedCategory = null;
                    _searchCtrl.clear();
                  });
                  _fetchPlaces();
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Reset Filters (50 km)'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      itemCount: _places.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) {
        final place = _places[i];
        final isSelected = _selectedPlace?.id == place.id;
        return _buildPlaceCard(place, isSelected);
      },
    );
  }

  String _emptyPlacesTitle() {
    final query = _searchCtrl.text.trim();
    if (query.isNotEmpty) {
      return 'No $query found within ${_radiusKm.toInt()} km';
    }
    return 'No stops found within ${_radiusKm.toInt()} km';
  }

  Widget _buildCategoryChip(
    PlaceCategory? cat,
    String label,
    IconData icon,
    Color iconColor,
  ) {
    final isSelected = _selectedCategory == cat;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedCategory = cat;
          _searchCtrl.clear();
        });
        _fetchPlaces();
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF23695A) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF23695A) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 19,
              height: 19,
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.18)
                    : iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 13,
                color: isSelected ? Colors.white : iconColor,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _categoryIcon(PlaceCategory category) {
    switch (category) {
      case PlaceCategory.restaurant:
        return Icons.restaurant_rounded;
      case PlaceCategory.fuel:
        return Icons.local_gas_station_rounded;
      case PlaceCategory.ev:
        return Icons.ev_station_rounded;
      case PlaceCategory.mechanic:
        return Icons.build_rounded;
      case PlaceCategory.tourist:
        return Icons.account_balance_rounded;
      case PlaceCategory.hospital:
        return Icons.local_hospital_rounded;
      case PlaceCategory.atm:
        return Icons.atm_rounded;
      case PlaceCategory.pharmacy:
        return Icons.local_pharmacy_rounded;
      case PlaceCategory.parking:
        return Icons.local_parking_rounded;
      case PlaceCategory.toilet:
        return Icons.wc_rounded;
    }
  }

  Color _categoryColor(PlaceCategory category) {
    switch (category) {
      case PlaceCategory.restaurant:
        return Colors.deepOrange;
      case PlaceCategory.fuel:
        return Colors.blue;
      case PlaceCategory.ev:
        return Colors.green;
      case PlaceCategory.mechanic:
        return Colors.deepPurple;
      case PlaceCategory.tourist:
        return Colors.amber.shade800;
      case PlaceCategory.hospital:
        return Colors.red;
      case PlaceCategory.atm:
        return Colors.indigo;
      case PlaceCategory.pharmacy:
        return Colors.pink;
      case PlaceCategory.parking:
        return Colors.blue.shade700;
      case PlaceCategory.toilet:
        return Colors.teal;
    }
  }

  Widget _buildPlaceCard(NearbyPlace place, bool isSelected) {
    return InkWell(
      onTap: () => _centerOnPlace(place),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF23695A)
                : const Color(0xFFE2E8F0),
            width: isSelected ? 1.8 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? const Color(0xFF23695A).withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Category, Distance, Open status
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6F3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: _categoryColor(place.category)
                              .withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _categoryIcon(place.category),
                          size: 12,
                          color: _categoryColor(place.category),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        place.categoryName,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF23695A),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Distance badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.near_me_rounded,
                        size: 11,
                        color: Color(0xFF23695A),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        place.formattedDistance,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                // Open status
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: place.isOpenNow
                        ? Colors.green.shade50
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    place.isOpenNow ? 'Open Now' : 'Closed',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: place.isOpenNow
                          ? Colors.green.shade800
                          : Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Row 2: Name & Rating
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    place.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      size: 16,
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      place.rating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    Text(
                      ' (${place.reviewsCount})',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),

            // Row 3: Address / Highway
            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 13,
                  color: Colors.grey,
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    place.address,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Row 4: Description
            Text(
              place.description,
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF475569),
                height: 1.35,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),

            // Row 5: Tags Chips
            Wrap(
              spacing: 5,
              runSpacing: 4,
              children: place.tags.take(3).map((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
            ),
            const Divider(height: 18),

            // Row 6: Live Action Buttons
            Row(
              children: [
                // 🧭 Navigate directly in NavGuardian App Map
                Expanded(
                  flex: 3,
                  child: FilledButton.icon(
                    onPressed: () => _navigateToPlaceWithNavGuardian(place),
                    icon: const Icon(Icons.navigation_rounded, size: 16),
                    label: const Text(
                      'Start Route',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF23695A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Show on preview map
                Expanded(
                  flex: 3,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _centerOnPlace(place);
                      _mapController?.showMarkerInfoWindow(MarkerId(place.id));
                    },
                    icon: const Icon(
                      Icons.pin_drop_outlined,
                      size: 15,
                      color: Color(0xFF23695A),
                    ),
                    label: const Text(
                      'Show on Map',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                        color: Color(0xFF23695A),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF23695A)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),

                // Call button if phone exists
                if (place.phone != null) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Call Place',
                    icon: const Icon(
                      Icons.call_rounded,
                      size: 18,
                      color: Color(0xFF23695A),
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFEFF6F3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () =>
                        NearbyPlacesService.callPlace(place.phone!),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
