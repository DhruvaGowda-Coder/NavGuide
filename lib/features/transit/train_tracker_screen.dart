import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../device/telephony/cell_tower_service.dart';
import '../../device/railway/train_tracking_engine.dart';
import '../../device/railway/train_alarm_engine.dart';
import 'station_picker_sheet.dart';
import 'station_alarm_sheet.dart';
import 'coach_layout_sheet.dart';
import '../../device/railway/online_train_service.dart';

enum TrackingMode {
  offlineSimGps,
  onlineInternet,
}

/// Next-Gen Train & Rail Transit HUD & Offline Search Screen for NavGuardian AI.
/// Fully matches the original NavGuardian Light Emerald (#23695a) theme.
class TrainTrackerScreen extends ConsumerStatefulWidget {
  const TrainTrackerScreen({super.key});

  @override
  ConsumerState<TrainTrackerScreen> createState() => _TrainTrackerScreenState();
}

class _TrainTrackerScreenState extends ConsumerState<TrainTrackerScreen> with SingleTickerProviderStateMixin {
  static const Color primaryEmerald = Color(0xff23695a);
  static const Color accentGreen = Color(0xff10b981);
  static const Color cardBg = Colors.white;
  static const Color textDark = Color(0xff1e293b);
  static const Color textMuted = Color(0xff64748b);
  static const Color scaffoldBg = Color(0xfff7f9f6);

  late TrainTrackingEngine _engine;
  bool _isLoading = true;

  // View Mode: 0 = Live HUD, 1 = Find Trains
  int _activeTab = 0;

  // Live HUD state
  TrainRoute? _selectedRoute;
  int _currentStationIndex = 1;
  double _distanceToNextKm = 3.4;
  int _speedKmh = 68;
  Timer? _simulationTimer;
  late AnimationController _pulseController;
  StreamSubscription<StationAlarm>? _alarmSubscription;

  // Dual Tracking Mode (Offline SIM/GPS vs Online Internet)
  TrackingMode _trackingMode = TrackingMode.offlineSimGps;
  LiveTrainStatus? _liveStatus;
  bool _isRefreshingOnline = false;

  LiveStationStatus? get _targetLiveStation {
    if (_liveStatus == null || _selectedRoute == null || _currentStationIndex >= _selectedRoute!.stations.length) return null;
    final code = _selectedRoute!.stations[_currentStationIndex].code;
    for (final s in _liveStatus!.stations) {
      if (s.stationCode == code) return s;
    }
    return null;
  }

  // Station-to-Station search state
  RailwayStation? _fromStation;
  RailwayStation? _toStation;
  final TextEditingController _trainQueryController = TextEditingController();
  List<TrainRoute> _searchResults = [];
  String? _expandedTimetableTrainNo;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _alarmSubscription = TrainAlarmEngine().onAlarmTriggered.listen((alarm) {
      if (mounted) {
        _showAlarmTriggeredDialog(alarm);
      }
    });

    _initEngine();
  }

  Future<void> _initEngine() async {
    _engine = ref.read(trainTrackingEngineProvider);
    await _engine.initialize();

    // Initial clean state: Find Trains tab is shown first without preselected route
    _selectedRoute = null;
    _fromStation = null;
    _toStation = null;
    _searchResults = [];

    if (mounted) {
      setState(() => _isLoading = false);
    }

    _simulationTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) return;
      setState(() {
        _speedKmh = 64 + (timer.tick % 15);
        if (_distanceToNextKm > 0.3) {
          _distanceToNextKm = (_distanceToNextKm - 0.1).clamp(0.1, 999.0);
        }

        // Proximity evaluation for destination alarm
        if (_selectedRoute != null && _currentStationIndex < _selectedRoute!.stations.length) {
          final targetStation = _selectedRoute!.stations[_currentStationIndex];
          final mins = ((_distanceToNextKm / (_speedKmh > 0 ? _speedKmh : 60)) * 60).round();
          TrainAlarmEngine().evaluateProximity(
            nextStationCode: targetStation.code,
            distanceToNextKm: _distanceToNextKm,
            estimatedMinsToNext: mins.toDouble(),
            routeHalts: _selectedRoute?.halts,
            currentStationIndex: _currentStationIndex,
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _alarmSubscription?.cancel();
    _pulseController.dispose();
    _trainQueryController.dispose();
    super.dispose();
  }

  void _searchStationToStation() {
    final from = _fromStation?.code ?? '';
    final to = _toStation?.code ?? '';
    setState(() {
      _searchResults = _engine.findTrainsBetween(from, to);
    });
  }

  void _onTrainQueryChanged(String query) {
    setState(() {
      if (query.trim().isEmpty) {
        _searchStationToStation();
      } else {
        _searchResults = _engine.searchTrains(query);
      }
    });
  }

  void _swapStations() {
    HapticFeedback.selectionClick();
    setState(() {
      final temp = _fromStation;
      _fromStation = _toStation;
      _toStation = temp;
      _searchStationToStation();
    });
  }

  void _trackTrain(TrainRoute route) {
    HapticFeedback.mediumImpact();
    setState(() {
      _selectedRoute = route;
      _currentStationIndex = 1;
      _distanceToNextKm = 4.2;
      _activeTab = 1; // Switch to Live Train HUD tab
    });
    if (_trackingMode == TrackingMode.onlineInternet) {
      _fetchLiveOnlineStatus();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Now tracking: ${route.trainName} (#${route.trainNumber})'),
        duration: const Duration(seconds: 2),
        backgroundColor: primaryEmerald,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cellTowerAsync = ref.watch(cellTowerProvider);

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: scaffoldBg,
        body: Center(
          child: CircularProgressIndicator(color: primaryEmerald),
        ),
      );
    }

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopTelemetryBar(cellTowerAsync),
            _buildTopModeSwitcher(),
            Expanded(
              child: _activeTab == 0
                  ? _buildFindTrainsView()
                  : _buildLiveHudView(cellTowerAsync),
            ),
          ],
        ),
      ),
    );
  }

  /// Top Telemetry Bar in clean original theme
  Widget _buildTopTelemetryBar(AsyncValue<CellTowerData> cellTowerAsync) {
    final tower = cellTowerAsync.asData?.value ?? CellTowerData.initial();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: primaryEmerald.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: primaryEmerald.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cell_tower_rounded, color: primaryEmerald, size: 16),
                const SizedBox(width: 6),
                Text(
                  tower.carrier.isNotEmpty ? tower.carrier.toUpperCase() : 'JIO 5G',
                  style: const TextStyle(
                    color: primaryEmerald,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tower.formattedTowerId,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                const Text(
                  '100% OFFLINE • TOWER SYNC',
                  style: TextStyle(
                    color: accentGreen,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          _buildSignalBars(tower.signalBars),
        ],
      ),
    );
  }

  Widget _buildSignalBars(int level) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (index) {
        final active = index < (level == 0 ? 3 : level);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          width: 4,
          height: 6.0 + (index * 3.5),
          decoration: BoxDecoration(
            color: active ? primaryEmerald : Colors.black12,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  /// Top View Selector: Live Tracking HUD vs Find Trains
  Widget _buildTopModeSwitcher() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _activeTab = 0);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _activeTab == 0 ? cardBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _activeTab == 0
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 16,
                      color: _activeTab == 0 ? primaryEmerald : textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Find Trains',
                      style: TextStyle(
                        color: _activeTab == 0 ? primaryEmerald : textMuted,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _activeTab = 1);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _activeTab == 1 ? cardBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _activeTab == 1
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.radar_rounded,
                      size: 16,
                      color: _activeTab == 1 ? primaryEmerald : textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Live Train HUD',
                      style: TextStyle(
                        color: _activeTab == 1 ? primaryEmerald : textMuted,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // LIVE TRACKING HUD VIEW
  // ===========================================================================
  Widget _buildLiveHudView(AsyncValue<CellTowerData> cellTowerAsync) {
    if (_selectedRoute == null) {
      return _buildEmptyLiveHudView();
    }

    final activeAlarm = TrainAlarmEngine().activeAlarm;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          _buildTrainSelectorHeader(),
          const SizedBox(height: 8),
          _buildTrackingModeSelectorBar(),
          if (_trackingMode == TrackingMode.onlineInternet) ...[
            const SizedBox(height: 8),
            _buildLiveOnlineStatusBanner(),
          ],
          if (activeAlarm != null) ...[
            const SizedBox(height: 8),
            _buildActiveAlarmBanner(activeAlarm),
          ],
          const SizedBox(height: 8),
          _buildHeroNextStationCard(cellTowerAsync),
          const SizedBox(height: 16),
          _buildStationTimeline(),
          SizedBox(height: 110 + MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Widget _buildEmptyLiveHudView() {
    final popular = _engine.getPopularRoutes();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: primaryEmerald.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.radar_rounded,
                    size: 34,
                    color: primaryEmerald,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'No Train Selected for Live HUD',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: textDark,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Select your journey in "Find Trains" or tap one of the popular trains below to activate real-time SIM tower & GPS tracking.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: textMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() => _activeTab = 0);
                  },
                  icon: const Icon(Icons.search_rounded, size: 18, color: Colors.white),
                  label: const Text(
                    'Go to Find Trains',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryEmerald,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'QUICK START POPULAR TRAINS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: textMuted,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 12),
                ...popular.take(3).map((r) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => _trackTrain(r),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: scaffoldBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: primaryEmerald.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '#${r.trainNumber}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: primaryEmerald,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              r.trainName,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: textDark,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: textMuted),
                        ],
                      ),
                    ),
                  ),
                )),
              ],
            ),
          ),
          SizedBox(height: 110 + MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Widget _buildActiveAlarmBanner(StationAlarm alarm) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: primaryEmerald.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primaryEmerald.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: primaryEmerald.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.alarm_on_rounded, color: primaryEmerald, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'STATION WAKE-UP ALARM ACTIVE',
                  style: TextStyle(
                    color: primaryEmerald,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                Text(
                  alarm.summaryText,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              HapticFeedback.selectionClick();
              TrainAlarmEngine().cancelAlarm();
              setState(() {});
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('CANCEL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildTrainSelectorHeader() {
    if (_selectedRoute == null) return const SizedBox.shrink();

    final hasAlarm = TrainAlarmEngine().activeAlarm != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: primaryEmerald.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _selectedRoute!.trainNumber,
              style: const TextStyle(
                color: primaryEmerald,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedRoute!.trainName,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${_selectedRoute!.trainType} • ${_selectedRoute!.duration}',
                  style: const TextStyle(color: textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              hasAlarm ? Icons.alarm_on_rounded : Icons.alarm_add_rounded,
              color: hasAlarm ? accentGreen : primaryEmerald,
            ),
            tooltip: 'Station Wake-up Alarm',
            onPressed: _openAlarmSheet,
          ),
          IconButton(
            icon: const Icon(Icons.view_carousel_rounded, color: primaryEmerald),
            tooltip: 'Coach Layout & Seat Guide',
            onPressed: _openCoachLayoutSheet,
          ),
          IconButton(
            icon: const Icon(Icons.swap_horiz_rounded, color: primaryEmerald),
            tooltip: 'Switch Train Route',
            onPressed: _showTrainPickerSheet,
          ),
        ],
      ),
    );
  }

  Widget _buildTrackingModeSelectorBar() {
    final isOnline = _trackingMode == TrackingMode.onlineInternet;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          // Offline SIM & GPS Mode
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _trackingMode = TrackingMode.offlineSimGps);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: !isOnline ? primaryEmerald : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.cell_tower_rounded,
                      size: 14,
                      color: !isOnline ? Colors.white : textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Offline (SIM & GPS)',
                      style: TextStyle(
                        color: !isOnline ? Colors.white : textMuted,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Online Internet Mode
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _trackingMode = TrackingMode.onlineInternet;
                  _fetchLiveOnlineStatus();
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isOnline ? primaryEmerald : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.wifi_rounded,
                      size: 14,
                      color: isOnline ? Colors.white : textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Online (Internet)',
                      style: TextStyle(
                        color: isOnline ? Colors.white : textMuted,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveOnlineStatusBanner() {
    if (_liveStatus == null) return const SizedBox.shrink();

    final isOnTime = _liveStatus!.isOnTime;
    final delayText = isOnTime ? 'ON TIME' : '${_liveStatus!.overallDelayMinutes}M DELAY';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isOnTime ? const Color(0xFFE8F5E9) : Colors.amber.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOnTime ? primaryEmerald.withValues(alpha: 0.3) : Colors.amber.shade400,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isOnTime ? primaryEmerald : Colors.amber.shade800,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              delayText,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 10,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _liveStatus!.statusSummary,
                  style: const TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'NTES Central Railway Server • Live Sync',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: _isRefreshingOnline
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: primaryEmerald),
                  )
                : const Icon(Icons.refresh_rounded, color: primaryEmerald, size: 20),
            tooltip: 'Refresh Live Status',
            onPressed: _isRefreshingOnline ? null : _fetchLiveOnlineStatus,
          ),
        ],
      ),
    );
  }

  Future<void> _fetchLiveOnlineStatus() async {
    if (_selectedRoute == null) return;
    setState(() => _isRefreshingOnline = true);
    try {
      final status = await OnlineTrainService().fetchLiveRunningStatus(_selectedRoute!);
      if (mounted) {
        setState(() {
          _liveStatus = status;
          _isRefreshingOnline = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isRefreshingOnline = false);
      }
    }
  }

  Widget _buildHeroNextStationCard(AsyncValue<CellTowerData> cellTowerAsync) {
    if (_selectedRoute == null || _currentStationIndex >= _selectedRoute!.stations.length) {
      return const SizedBox.shrink();
    }

    final targetStation = _selectedRoute!.stations[_currentStationIndex];
    final minutesRemaining = ((_distanceToNextKm / (_speedKmh > 0 ? _speedKmh : 60)) * 60).round();
    final hasAlarm = TrainAlarmEngine().activeAlarm != null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primaryEmerald.withValues(alpha: 0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: primaryEmerald.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accentGreen,
                          boxShadow: [
                            BoxShadow(
                              color: accentGreen.withValues(alpha: 0.6 * _pulseController.value),
                              blurRadius: 10 * _pulseController.value,
                              spreadRadius: 3 * _pulseController.value,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'NEXT STATION',
                    style: TextStyle(
                      color: primaryEmerald,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: _openAlarmSheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: hasAlarm
                            ? primaryEmerald
                            : primaryEmerald.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasAlarm ? Icons.alarm_on_rounded : Icons.alarm_add_rounded,
                            color: hasAlarm ? Colors.white : primaryEmerald,
                            size: 13,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            hasAlarm ? 'Alarm Set' : 'Set Alarm',
                            style: TextStyle(
                              color: hasAlarm ? Colors.white : primaryEmerald,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: _trackingMode == TrackingMode.onlineInternet
                          ? (_liveStatus?.isOnTime ?? true ? const Color(0xFFE8F5E9) : Colors.amber.shade50)
                          : primaryEmerald.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _trackingMode == TrackingMode.onlineInternet ? Icons.wifi_rounded : Icons.speed_rounded,
                          color: _trackingMode == TrackingMode.onlineInternet
                              ? (_liveStatus?.isOnTime ?? true ? primaryEmerald : Colors.amber.shade900)
                              : primaryEmerald,
                          size: 13,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _trackingMode == TrackingMode.onlineInternet
                              ? (_liveStatus?.isOnTime ?? true ? 'Right Time' : '+${_liveStatus!.overallDelayMinutes}m Late')
                              : '$_speedKmh km/h',
                          style: TextStyle(
                            color: _trackingMode == TrackingMode.onlineInternet
                                ? (_liveStatus?.isOnTime ?? true ? primaryEmerald : Colors.amber.shade900)
                                : textDark,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            targetStation.name,
            style: const TextStyle(
              color: textDark,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${targetStation.code} • ${targetStation.city}, ${targetStation.state}',
            style: const TextStyle(
              color: textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: scaffoldBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _trackingMode == TrackingMode.onlineInternet ? 'EXP. ARRIVAL' : 'DISTANCE',
                        style: const TextStyle(color: textMuted, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _trackingMode == TrackingMode.onlineInternet
                            ? (_targetLiveStation?.expectedArrival ?? targetStation.code)
                            : '${_distanceToNextKm.toStringAsFixed(1)} km',
                        style: const TextStyle(
                          color: primaryEmerald,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: scaffoldBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _trackingMode == TrackingMode.onlineInternet ? 'LIVE PLATFORM' : 'EST. ARRIVAL',
                        style: const TextStyle(color: textMuted, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _trackingMode == TrackingMode.onlineInternet
                            ? (_targetLiveStation?.platform ?? 'PF 1')
                            : '~$minutesRemaining mins',
                        style: const TextStyle(
                          color: primaryEmerald,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: _openCoachLayoutSheet,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: primaryEmerald.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: primaryEmerald.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.view_carousel_rounded, color: primaryEmerald, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Coach Layout & Seat Position',
                    style: TextStyle(
                      color: primaryEmerald,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'View Rake',
                    style: TextStyle(
                      color: primaryEmerald,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_ios_rounded, color: primaryEmerald, size: 10),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStationTimeline() {
    if (_selectedRoute == null) return const SizedBox.shrink();

    final halts = _selectedRoute!.halts;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'JOURNEY TIMELINE',
                style: TextStyle(
                  color: textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                '${halts.length} STATIONS',
                style: const TextStyle(
                  color: primaryEmerald,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: halts.length,
            itemBuilder: (context, index) {
              final halt = halts[index];
              final station = halt.station;
              final isPassed = index < _currentStationIndex;
              final isCurrentTarget = index == _currentStationIndex;
              final isLast = index == halts.length - 1;

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isPassed
                                ? primaryEmerald
                                : (isCurrentTarget ? accentGreen : Colors.grey.shade200),
                            border: Border.all(
                              color: isCurrentTarget ? primaryEmerald : (isPassed ? primaryEmerald : Colors.grey.shade400),
                              width: isCurrentTarget ? 2 : 1,
                            ),
                          ),
                          child: Icon(
                            isPassed ? Icons.check : (isCurrentTarget ? Icons.directions_railway : Icons.circle),
                            size: isPassed ? 14 : (isCurrentTarget ? 14 : 6),
                            color: isPassed || isCurrentTarget ? Colors.white : Colors.grey.shade500,
                          ),
                        ),
                        if (!isLast)
                          Expanded(
                            child: Container(
                              width: 2,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              color: isPassed
                                  ? primaryEmerald
                                  : (isCurrentTarget
                                      ? primaryEmerald.withValues(alpha: 0.4)
                                      : Colors.grey.shade300),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    station.name,
                                    style: TextStyle(
                                      color: isCurrentTarget
                                          ? textDark
                                          : (isPassed ? textMuted : Colors.grey.shade600),
                                      fontSize: 15,
                                      fontWeight: isCurrentTarget ? FontWeight.w800 : FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isCurrentTarget
                                        ? primaryEmerald.withValues(alpha: 0.1)
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    station.code,
                                    style: TextStyle(
                                      color: isCurrentTarget ? primaryEmerald : textMuted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Builder(
                              builder: (context) {
                                final isOnline = _trackingMode == TrackingMode.onlineInternet && _liveStatus != null;
                                LiveStationStatus? liveHalt;
                                if (isOnline) {
                                  for (final s in _liveStatus!.stations) {
                                    if (s.stationCode == station.code) {
                                      liveHalt = s;
                                      break;
                                    }
                                  }
                                }

                                String timingText;
                                if (isPassed) {
                                  timingText = 'Passed • Dep: ${halt.departureTime}';
                                } else if (isCurrentTarget) {
                                  timingText = isOnline
                                      ? 'Approaching (Exp: ${liveHalt?.expectedArrival ?? halt.arrivalTime})'
                                      : 'Approaching (${_distanceToNextKm.toStringAsFixed(1)} km away)';
                                } else {
                                  timingText = isOnline
                                      ? 'Exp: ${liveHalt?.expectedArrival ?? halt.arrivalTime} • Dep: ${liveHalt?.expectedDeparture ?? halt.departureTime}'
                                      : 'Arr: ${halt.arrivalTime} • Dep: ${halt.departureTime}';
                                }

                                return Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        timingText,
                                        style: TextStyle(
                                          color: isCurrentTarget ? primaryEmerald : textMuted,
                                          fontSize: 12,
                                          fontWeight: isCurrentTarget ? FontWeight.w600 : FontWeight.normal,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isOnline && liveHalt != null && !isPassed) ...[
                                          Container(
                                            margin: const EdgeInsets.only(right: 6),
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: liveHalt.delayMinutes <= 0
                                                  ? const Color(0xFFE8F5E9)
                                                  : Colors.amber.shade50,
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(
                                                color: liveHalt.delayMinutes <= 0
                                                    ? primaryEmerald.withValues(alpha: 0.3)
                                                    : Colors.amber.shade300,
                                              ),
                                            ),
                                            child: Text(
                                              liveHalt.delayBadgeText,
                                              style: TextStyle(
                                                color: liveHalt.delayMinutes <= 0
                                                    ? primaryEmerald
                                                    : Colors.amber.shade900,
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                        Text(
                                          halt.platform,
                                          style: TextStyle(
                                            color: isCurrentTarget ? primaryEmerald : textMuted,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (!isPassed) ...[
                                          const SizedBox(width: 8),
                                          GestureDetector(
                                            onTap: () => _openAlarmSheetForHalt(halt),
                                            child: Icon(
                                              TrainAlarmEngine().activeAlarm?.targetStationCode == station.code
                                                  ? Icons.alarm_on_rounded
                                                  : Icons.alarm_add_outlined,
                                              size: 15,
                                              color: TrainAlarmEngine().activeAlarm?.targetStationCode == station.code
                                                  ? accentGreen
                                                  : textMuted.withValues(alpha: 0.6),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _openAlarmSheet() {
    if (_selectedRoute == null) return;
    HapticFeedback.lightImpact();
    StationAlarmSheet.show(
      context,
      route: _selectedRoute!,
      currentStationIndex: _currentStationIndex,
      onAlarmSet: (alarm) {
        TrainAlarmEngine().setAlarm(alarm);
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Alarm set: ${alarm.summaryText}'),
            backgroundColor: primaryEmerald,
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }

  void _openCoachLayoutSheet({String? coachCode}) {
    if (_selectedRoute == null) return;
    HapticFeedback.lightImpact();
    CoachLayoutSheet.show(
      context,
      route: _selectedRoute!,
      initialCoachCode: coachCode,
    );
  }

  void _openAlarmSheetForHalt(StationHalt halt) {
    if (_selectedRoute == null) return;
    HapticFeedback.lightImpact();
    final defaultAlarm = StationAlarm(
      targetStationCode: halt.station.code,
      targetStationName: halt.station.name,
      mode: AlarmTriggerMode.distance,
      triggerValue: 10.0,
      enableVibration: true,
      enableSound: true,
    );
    TrainAlarmEngine().setAlarm(defaultAlarm);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Alarm set: 10 km before ${halt.station.name} (${halt.station.code})'),
        backgroundColor: primaryEmerald,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showAlarmTriggeredDialog(StationAlarm alarm) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: Colors.white,
          contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: primaryEmerald.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: primaryEmerald,
                  size: 34,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'WAKE UP!',
                style: TextStyle(
                  color: primaryEmerald,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Approaching ${alarm.targetStationName}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: textDark,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: scaffoldBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                ),
                child: Text(
                  alarm.summaryText,
                  style: const TextStyle(
                    color: textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textDark,
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      TrainAlarmEngine().snoozeAlarm(minutes: 5);
                      Navigator.pop(ctx);
                      setState(() {});
                    },
                    child: const Text('Snooze (5m)', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryEmerald,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      TrainAlarmEngine().dismissAlarm();
                      Navigator.pop(ctx);
                      setState(() {});
                    },
                    child: const Text('Dismiss', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _showTrainPickerSheet() {
    final routes = _engine.getPopularRoutes();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).padding.bottom;
        return Container(
          decoration: const BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            bottom: true,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Select Train Route',
                    style: TextStyle(
                      color: textDark,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...routes.map((route) {
                    final isSelected = _selectedRoute?.trainNumber == route.trainNumber;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? primaryEmerald.withValues(alpha: 0.06)
                            : scaffoldBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? primaryEmerald.withValues(alpha: 0.3)
                              : Colors.black.withValues(alpha: 0.05),
                        ),
                      ),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? primaryEmerald.withValues(alpha: 0.15)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.train_rounded,
                            color: isSelected ? primaryEmerald : textMuted,
                          ),
                        ),
                        title: Text(
                          route.trainName,
                          style: TextStyle(
                            color: isSelected ? primaryEmerald : textDark,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          'Train #${route.trainNumber} • ${route.stations.length} Stations • ${route.duration}',
                          style: const TextStyle(color: textMuted, fontSize: 12),
                        ),
                        trailing: isSelected
                            ? const Icon(
                                Icons.check_circle_rounded,
                                color: primaryEmerald,
                              )
                            : null,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _selectedRoute = route;
                            _currentStationIndex = 1;
                            _distanceToNextKm = 4.2;
                          });
                          Navigator.pop(ctx);
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // FIND TRAINS (STATION-TO-STATION & NUMBER SEARCH) VIEW
  // ===========================================================================
  Widget _buildFindTrainsView() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStationSearchCard(),
          const SizedBox(height: 12),
          _buildTrainNumberSearchBar(),
          const SizedBox(height: 16),
          if (_searchResults.isEmpty && _fromStation == null && _toStation == null && _trainQueryController.text.trim().isEmpty)
            _buildEmptyFindTrainsPrompt()
          else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'AVAILABLE TRAINS (${_searchResults.length})',
                  style: const TextStyle(
                    color: textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                if (_fromStation != null && _toStation != null)
                  Text(
                    '${_fromStation!.code} ➔ ${_toStation!.code}',
                    style: const TextStyle(
                      color: primaryEmerald,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _searchResults.isEmpty
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.search_off_rounded, size: 48, color: textMuted.withValues(alpha: 0.5)),
                        const SizedBox(height: 12),
                        const Text(
                          'No direct trains found',
                          style: TextStyle(color: textDark, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Try selecting a different station pair or search by train number.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final route = _searchResults[index];
                      final isExpanded = _expandedTimetableTrainNo == route.trainNumber;

                      return _buildTrainSearchResultCard(route, isExpanded);
                    },
                  ),
          ],
          SizedBox(height: 110 + MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Widget _buildEmptyFindTrainsPrompt() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: primaryEmerald.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search_rounded,
              size: 36,
              color: primaryEmerald,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Select Stations to Find Trains',
            style: TextStyle(
              color: textDark,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Pick your origin and destination stations above to see direct trains and offline schedules.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textMuted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'POPULAR DIRECT ROUTES',
              style: TextStyle(
                color: textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildQuickRouteChip('Bengaluru', 'SBC', 'Chennai', 'MAS'),
              _buildQuickRouteChip('Bengaluru', 'SBC', 'Mysuru', 'MYS'),
              _buildQuickRouteChip('Chennai', 'MAS', 'Bengaluru', 'SBC'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickRouteChip(String fromName, String fromCode, String toName, String toCode) {
    return ActionChip(
      onPressed: () {
        HapticFeedback.selectionClick();
        setState(() {
          _fromStation = _engine.getStationByCode(fromCode);
          _toStation = _engine.getStationByCode(toCode);
          _searchStationToStation();
        });
      },
      avatar: const Icon(Icons.route_rounded, size: 14, color: primaryEmerald),
      label: Text(
        '$fromName ➔ $toName',
        style: const TextStyle(
          color: textDark,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: scaffoldBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: primaryEmerald.withValues(alpha: 0.2)),
      ),
    );
  }

  Widget _buildStationSearchCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // From Station Box
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final selected = await StationPickerSheet.show(
                context: context,
                title: 'Select From Station',
                engine: _engine,
                currentSelectedCode: _fromStation?.code,
              );
              if (selected != null) {
                setState(() {
                  _fromStation = selected;
                  _searchStationToStation();
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: scaffoldBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.trip_origin_rounded, color: primaryEmerald, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'FROM STATION',
                          style: TextStyle(color: textMuted, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _fromStation != null
                              ? '${_fromStation!.name} (${_fromStation!.code})'
                              : 'Tap to select origin station',
                          style: const TextStyle(
                            color: textDark,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down_rounded, color: textMuted),
                ],
              ),
            ),
          ),
          // Swap Button Row
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: primaryEmerald.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.swap_vert_rounded, color: primaryEmerald, size: 20),
                ),
                tooltip: 'Swap From and To Stations',
                onPressed: _swapStations,
              ),
            ),
          ),
          // To Station Box
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final selected = await StationPickerSheet.show(
                context: context,
                title: 'Select To Station',
                engine: _engine,
                currentSelectedCode: _toStation?.code,
              );
              if (selected != null) {
                setState(() {
                  _toStation = selected;
                  _searchStationToStation();
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: scaffoldBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on_rounded, color: primaryEmerald, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TO STATION',
                          style: TextStyle(color: textMuted, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _toStation != null
                              ? '${_toStation!.name} (${_toStation!.code})'
                              : 'Tap to select destination station',
                          style: const TextStyle(
                            color: textDark,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down_rounded, color: textMuted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrainNumberSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: TextField(
        controller: _trainQueryController,
        onChanged: _onTrainQueryChanged,
        style: const TextStyle(color: textDark, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Or search by Train No. or Name (e.g. 12657, Vande Bharat)',
          hintStyle: const TextStyle(color: textMuted, fontSize: 13),
          prefixIcon: const Icon(Icons.search_rounded, color: primaryEmerald),
          suffixIcon: _trainQueryController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18, color: textMuted),
                  onPressed: () {
                    _trainQueryController.clear();
                    _onTrainQueryChanged('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildTrainSearchResultCard(TrainRoute route, bool isExpanded) {
    final isCurrentTracking = _selectedRoute?.trainNumber == route.trainNumber;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrentTracking
              ? primaryEmerald.withValues(alpha: 0.3)
              : Colors.black.withValues(alpha: 0.06),
          width: isCurrentTracking ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: primaryEmerald.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#${route.trainNumber}',
                        style: const TextStyle(
                          color: primaryEmerald,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: scaffoldBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                      ),
                      child: Text(
                        route.trainType,
                        style: const TextStyle(
                          color: textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  route.trainName,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            route.departureTime,
                            style: const TextStyle(
                              color: textDark,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            route.sourceStation.name,
                            style: const TextStyle(color: textMuted, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          Text(
                            route.duration,
                            style: const TextStyle(
                              color: primaryEmerald,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(width: 14, height: 1, color: Colors.grey.shade400),
                              const Icon(Icons.arrow_forward_rounded, size: 14, color: primaryEmerald),
                              Container(width: 14, height: 1, color: Colors.grey.shade400),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${route.halts.length} halts',
                            style: const TextStyle(color: textMuted, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            route.arrivalTime,
                            style: const TextStyle(
                              color: textDark,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            route.destinationStation.name,
                            style: const TextStyle(color: textMuted, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primaryEmerald,
                          side: const BorderSide(color: primaryEmerald),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        icon: Icon(
                          isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.schedule_rounded,
                          size: 16,
                        ),
                        label: Text(isExpanded ? 'Hide Schedule' : 'View Timetable'),
                        onPressed: () {
                          setState(() {
                            _expandedTimetableTrainNo = isExpanded ? null : route.trainNumber;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: primaryEmerald,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        icon: const Icon(Icons.radar_rounded, size: 16),
                        label: const Text('Track Live'),
                        onPressed: () => _trackTrain(route),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      style: IconButton.styleFrom(
                        side: const BorderSide(color: primaryEmerald),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.all(10),
                      ),
                      icon: const Icon(Icons.view_carousel_rounded, size: 18, color: primaryEmerald),
                      tooltip: 'Coach Layout & Seat Map',
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        CoachLayoutSheet.show(context, route: route);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isExpanded) _buildExpandedTimetable(route),
        ],
      ),
    );
  }

  Widget _buildExpandedTimetable(TrainRoute route) {
    return Container(
      decoration: BoxDecoration(
        color: scaffoldBg,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        border: Border(top: BorderSide(color: Colors.black.withValues(alpha: 0.05))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'STATION / CODE',
                style: TextStyle(color: textMuted, fontSize: 10, fontWeight: FontWeight.bold),
              ),
              Text(
                'ARR / DEP • PF',
                style: TextStyle(color: textMuted, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...route.halts.map((halt) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: primaryEmerald,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          halt.station.name,
                          style: const TextStyle(color: textDark, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        Text(
                          '${halt.station.code} • ${halt.distanceKm.toStringAsFixed(0)} km',
                          style: const TextStyle(color: textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${halt.arrivalTime} - ${halt.departureTime}',
                        style: const TextStyle(color: textDark, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      Text(
                        '${halt.platform} ${halt.haltMinutes > 0 ? '(${halt.haltMinutes}m)' : ''}',
                        style: const TextStyle(color: primaryEmerald, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
