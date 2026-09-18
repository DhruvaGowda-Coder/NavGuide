import 'package:flutter/material.dart';
import '../../device/railway/train_tracking_engine.dart';
import '../../device/railway/train_alarm_engine.dart';

class StationAlarmSheet extends StatefulWidget {
  final TrainRoute route;
  final int currentStationIndex;
  final Function(StationAlarm) onAlarmSet;

  const StationAlarmSheet({
    super.key,
    required this.route,
    required this.currentStationIndex,
    required this.onAlarmSet,
  });

  static Future<void> show(
    BuildContext context, {
    required TrainRoute route,
    required int currentStationIndex,
    required Function(StationAlarm) onAlarmSet,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StationAlarmSheet(
        route: route,
        currentStationIndex: currentStationIndex,
        onAlarmSet: onAlarmSet,
      ),
    );
  }

  @override
  State<StationAlarmSheet> createState() => _StationAlarmSheetState();
}

class _StationAlarmSheetState extends State<StationAlarmSheet> {
  late String _selectedStationCode;
  AlarmTriggerMode _triggerMode = AlarmTriggerMode.distance;
  double _selectedDistanceKm = 10.0;
  double _selectedTimeMins = 15.0;
  bool _enableVibration = true;
  bool _enableSound = true;

  @override
  void initState() {
    super.initState();
    final halts = _upcomingHalts;
    if (halts.isNotEmpty) {
      _selectedStationCode = halts.last.station.code;
    } else {
      _selectedStationCode = widget.route.destinationStation.code;
    }
  }

  List<StationHalt> get _upcomingHalts {
    final halts = widget.route.halts;
    if (widget.currentStationIndex < halts.length) {
      return halts.sublist(widget.currentStationIndex);
    }
    return halts;
  }

  StationHalt? get _selectedHalt {
    for (final h in widget.route.halts) {
      if (h.station.code == _selectedStationCode) return h;
    }
    return widget.route.halts.isNotEmpty ? widget.route.halts.last : null;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final systemPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 14, 20, 24 + systemPadding + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF23695a).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.alarm_add_rounded,
                  color: Color(0xFF23695a),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Station Destination Alarm',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    Text(
                      'Wake up before reaching your station (100% Offline)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Destination Station Selector
          Text(
            'TARGET STATION',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _selectedStationCode,
                icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF23695a)),
                items: _upcomingHalts.map((halt) {
                  return DropdownMenuItem<String>(
                    value: halt.station.code,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF23695a).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            halt.station.code,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF23695a),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            halt.station.name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E293B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedStationCode = val);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Trigger Mode Toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'WAKE-UP TIMING',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: Colors.grey.shade600,
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    _buildModeTab('Distance', AlarmTriggerMode.distance),
                    _buildModeTab('Time', AlarmTriggerMode.time),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Quick Preset Chips
          if (_triggerMode == AlarmTriggerMode.distance)
            Wrap(
              spacing: 8,
              children: [5.0, 10.0, 15.0, 20.0].map((dist) {
                final isSelected = _selectedDistanceKm == dist;
                return ChoiceChip(
                  label: Text('${dist.toInt()} km before'),
                  selected: isSelected,
                  selectedColor: const Color(0xFF23695a),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF1E293B),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  backgroundColor: const Color(0xFFF1F5F9),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: isSelected ? const Color(0xFF23695a) : Colors.transparent,
                    ),
                  ),
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedDistanceKm = dist);
                  },
                );
              }).toList(),
            )
          else
            Wrap(
              spacing: 8,
              children: [10.0, 15.0, 20.0, 30.0].map((mins) {
                final isSelected = _selectedTimeMins == mins;
                return ChoiceChip(
                  label: Text('${mins.toInt()} mins before'),
                  selected: isSelected,
                  selectedColor: const Color(0xFF23695a),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF1E293B),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  backgroundColor: const Color(0xFFF1F5F9),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: isSelected ? const Color(0xFF23695a) : Colors.transparent,
                    ),
                  ),
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedTimeMins = mins);
                  },
                );
              }).toList(),
            ),

          const SizedBox(height: 18),

          // Toggles for Sound and Vibration
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text(
                    'Continuous Haptic Vibration',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Strong vibrations even if screen is off',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  value: _enableVibration,
                  activeTrackColor: const Color(0xFF23695a).withValues(alpha: 0.5),
                  activeThumbColor: const Color(0xFF23695a),
                  onChanged: (val) => setState(() => _enableVibration = val),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text(
                    'Loud Alarm Ringtone',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Sounds alarm when threshold is reached',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  value: _enableSound,
                  activeTrackColor: const Color(0xFF23695a).withValues(alpha: 0.5),
                  activeThumbColor: const Color(0xFF23695a),
                  onChanged: (val) => setState(() => _enableSound = val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Set Alarm Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () {
                final halt = _selectedHalt;
                final stationCode = halt?.station.code ?? _selectedStationCode;
                final stationName = halt?.station.name ?? _selectedStationCode;

                final alarm = StationAlarm(
                  targetStationCode: stationCode,
                  targetStationName: stationName,
                  mode: _triggerMode,
                  triggerValue: _triggerMode == AlarmTriggerMode.distance
                      ? _selectedDistanceKm
                      : _selectedTimeMins,
                  enableVibration: _enableVibration,
                  enableSound: _enableSound,
                );
                widget.onAlarmSet(alarm);
                Navigator.pop(context);
              },
              icon: const Icon(Icons.check_circle_rounded, color: Colors.white),
              label: Text(
                'SET ALARM FOR $_selectedStationCode',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF23695a),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeTab(String title, AlarmTriggerMode mode) {
    final isSelected = _triggerMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _triggerMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF23695a) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}
