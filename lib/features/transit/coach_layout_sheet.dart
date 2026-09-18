import 'package:flutter/material.dart';
import '../../device/railway/coach_layout_engine.dart';
import '../../device/railway/train_tracking_engine.dart';

class CoachLayoutSheet extends StatefulWidget {
  final TrainRoute route;
  final String? initialCoachCode;

  const CoachLayoutSheet({
    super.key,
    required this.route,
    this.initialCoachCode,
  });

  static Future<void> show(
    BuildContext context, {
    required TrainRoute route,
    String? initialCoachCode,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CoachLayoutSheet(
        route: route,
        initialCoachCode: initialCoachCode,
      ),
    );
  }

  @override
  State<CoachLayoutSheet> createState() => _CoachLayoutSheetState();
}

class _CoachLayoutSheetState extends State<CoachLayoutSheet> {
  late List<CoachInfo> _coaches;
  late int _selectedCoachIndex;
  final TextEditingController _seatController = TextEditingController();
  SeatInfo? _foundSeat;

  @override
  void initState() {
    super.initState();
    _coaches = CoachLayoutEngine().getCompositionForTrain(widget.route.trainNumber);
    _selectedCoachIndex = 0;

    // Default to first sleeper / reserved passenger coach if possible
    if (_coaches.isNotEmpty) {
      final preferredIndex = _coaches.indexWhere((c) =>
          c.type == CoachType.sleeper ||
          c.type == CoachType.ac3Tier ||
          c.type == CoachType.chairCar);
      if (preferredIndex != -1) {
        _selectedCoachIndex = preferredIndex;
      } else {
        final firstPassengerIndex = _coaches.indexWhere((c) =>
            c.type != CoachType.locoEngine && c.type != CoachType.guardSlr);
        if (firstPassengerIndex != -1) {
          _selectedCoachIndex = firstPassengerIndex;
        }
      }
    }

    if (widget.initialCoachCode != null) {
      final idx = _coaches.indexWhere((c) => c.coachCode.toLowerCase() == widget.initialCoachCode!.toLowerCase());
      if (idx != -1) _selectedCoachIndex = idx;
    }

    // Default seat lookup to seat 21
    _seatController.text = '21';
    _updateSeatLookup(21);
  }

  @override
  void dispose() {
    _seatController.dispose();
    super.dispose();
  }

  CoachInfo get _currentCoach => _coaches[_selectedCoachIndex];

  void _updateSeatLookup(int? seatNum) {
    if (seatNum == null || seatNum < 1) {
      setState(() => _foundSeat = null);
      return;
    }
    setState(() {
      _foundSeat = _currentCoach.resolveSeat(seatNum);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final systemPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF7F9F6),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.view_carousel_rounded,
                    color: Color(0xFF23695A),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            widget.route.trainNumber,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF23695A),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'OFFLINE RAKE',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${widget.route.trainName} Coach Layout',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.black54),
                ),
              ],
            ),
          ),
          const Divider(height: 20, thickness: 1, color: Color(0xFFE2E8F0)),

          // Scrollable Content
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + systemPadding + bottomInset),
              children: [
                // Direction Indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blueGrey.shade100),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.arrow_back_rounded, size: 14, color: Color(0xFF475569)),
                      SizedBox(width: 6),
                      Text(
                        'ENGINE DIRECTION (FRONT TO REAR)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: Color(0xFF475569),
                        ),
                      ),
                      Spacer(),
                      Text(
                        'TAP COACH TO INSPECT',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),

                // Horizontal Coach Rake Bar
                SizedBox(
                  height: 94,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _coaches.length,
                    separatorBuilder: (_, __) => Center(
                      child: Container(
                        width: 8,
                        height: 4,
                        color: Colors.grey.shade400,
                      ),
                    ),
                    itemBuilder: (context, index) {
                      final coach = _coaches[index];
                      final isSelected = index == _selectedCoachIndex;
                      final isLoco = coach.type == CoachType.locoEngine;

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedCoachIndex = index;
                            if (_seatController.text.isNotEmpty) {
                              _updateSeatLookup(int.tryParse(_seatController.text));
                            }
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: isLoco ? 86 : 74,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFFE8F5E9)
                                : isLoco
                                    ? Colors.amber.shade50
                                    : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF23695A)
                                  : isLoco
                                      ? Colors.amber.shade300
                                      : Colors.grey.shade300,
                              width: isSelected ? 2 : 1,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFF23695A).withValues(alpha: 0.15),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    )
                                  ]
                                : [],
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isLoco
                                    ? Icons.train_rounded
                                    : coach.type == CoachType.pantry
                                        ? Icons.restaurant_rounded
                                        : coach.type == CoachType.guardSlr
                                            ? Icons.luggage_rounded
                                            : Icons.directions_railway_rounded,
                                size: 20,
                                color: isSelected
                                    ? const Color(0xFF23695A)
                                    : isLoco
                                        ? Colors.amber.shade800
                                        : Colors.grey.shade600,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                coach.coachCode,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: isSelected ? const Color(0xFF23695A) : const Color(0xFF1E293B),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                coach.coachName,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? const Color(0xFF1C5246) : Colors.grey.shade600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),

                // Selected Coach Detail Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF23695A),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _currentCoach.coachCode,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _currentCoach.typeDescription,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                Text(
                                  _currentCoach.totalBerths > 0
                                      ? '${_currentCoach.totalBerths} Berths / Seats Capacity'
                                      : 'No Passenger Berths',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Coach ${_selectedCoachIndex + 1}/${_coaches.length}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_currentCoach.totalBerths > 0) ...[
                        const Divider(height: 24, thickness: 1, color: Color(0xFFF1F5F9)),
                        // Berth Legend
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _buildLegendItem('LB', 'Lower', Colors.indigo.shade50, Colors.indigo.shade800),
                            _buildLegendItem('MB', 'Middle', Colors.cyan.shade50, Colors.cyan.shade800),
                            _buildLegendItem('UB', 'Upper', Colors.deepPurple.shade50, Colors.deepPurple.shade800),
                            _buildLegendItem('SL', 'Side Lower', Colors.teal.shade50, Colors.teal.shade800),
                            _buildLegendItem('SU', 'Side Upper', Colors.orange.shade50, Colors.orange.shade800),
                            _buildLegendItem('W', 'Window', const Color(0xFFE8F5E9), const Color(0xFF23695A)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Interactive Seat Finder & Berth Calculator
                if (_currentCoach.totalBerths > 0) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.airline_seat_recline_normal_rounded, color: Color(0xFF23695A), size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Interactive Seat & Berth Finder',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Enter your seat number to locate your berth type, bay position, and window side inside coach ${_currentCoach.coachCode}:',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Seat Input + Quick Chips
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _seatController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  hintText: 'e.g. 21',
                                  labelText: 'Seat / Berth #',
                                  labelStyle: const TextStyle(color: Color(0xFF23695A), fontSize: 13),
                                  prefixIcon: const Icon(Icons.tag_rounded, color: Color(0xFF23695A), size: 20),
                                  filled: true,
                                  fillColor: const Color(0xFFF7F9F6),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(color: Color(0xFF23695A), width: 1.8),
                                  ),
                                ),
                                onChanged: (val) {
                                  final num = int.tryParse(val.trim());
                                  _updateSeatLookup(num);
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Quick Seat Chips
                            Expanded(
                              flex: 3,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [1, 7, 18, 21, 35, 63].map((seat) {
                                    final isSelected = _foundSeat?.seatNumber == seat;
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: ActionChip(
                                        label: Text('#$seat'),
                                        labelStyle: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: isSelected ? Colors.white : const Color(0xFF23695A),
                                        ),
                                        backgroundColor: isSelected ? const Color(0xFF23695A) : const Color(0xFFE8F5E9),
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                        onPressed: () {
                                          _seatController.text = '$seat';
                                          _updateSeatLookup(seat);
                                        },
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Berth Result Box
                        if (_foundSeat != null) ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F8F5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF23695A).withValues(alpha: 0.3)),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF23695A),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.check_circle_rounded,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _foundSeat!.berthName,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF1E293B),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Seat ${_foundSeat!.seatNumber} • ${_currentCoach.coachCode} • Bay ${_foundSeat!.bayNumber}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_foundSeat!.isWindow)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.shade100,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.amber.shade400),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.wb_sunny_rounded, size: 12, color: Colors.amber.shade900),
                                            const SizedBox(width: 4),
                                            Text(
                                              'WINDOW',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.amber.shade900,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 14),

                                // Visual Bay Layout Grid
                                _buildBayVisualGrid(_foundSeat!, _currentCoach),
                              ],
                            ),
                          ),
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline_rounded, color: Colors.red.shade700, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Please enter a valid seat number between 1 and ${_currentCoach.totalBerths} for ${_currentCoach.coachCode}.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.red.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, color: Colors.grey.shade600),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${_currentCoach.coachName} does not have reserved passenger seats or berths.',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String code, String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            code,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg),
          ),
        ],
      ),
    );
  }

  Widget _buildBayVisualGrid(SeatInfo seat, CoachInfo coach) {
    final bay = seat.bayNumber;
    final isSleeper3A = coach.type == CoachType.sleeper || coach.type == CoachType.ac3Tier;
    final is2A = coach.type == CoachType.ac2Tier;

    if (isSleeper3A) {
      final base = (bay - 1) * 8;
      final lb1 = base + 1;
      final mb1 = base + 2;
      final ub1 = base + 3;
      final lb2 = base + 4;
      final mb2 = base + 5;
      final ub2 = base + 6;
      final sl = base + 7;
      final su = base + 8;

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'COMPARTMENT BAY $bay LAYOUT',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF64748B),
                    letterSpacing: 0.5,
                  ),
                ),
                const Text(
                  '◄ WINDOW SIDE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF23695A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                // Main Cab (6 berths)
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _buildMiniBerthBox(lb1, 'LB', seat.seatNumber == lb1, isWindow: true)),
                          const SizedBox(width: 4),
                          Expanded(child: _buildMiniBerthBox(mb1, 'MB', seat.seatNumber == mb1)),
                          const SizedBox(width: 4),
                          Expanded(child: _buildMiniBerthBox(ub1, 'UB', seat.seatNumber == ub1)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _buildMiniBerthBox(lb2, 'LB', seat.seatNumber == lb2, isWindow: true)),
                          const SizedBox(width: 4),
                          Expanded(child: _buildMiniBerthBox(mb2, 'MB', seat.seatNumber == mb2)),
                          const SizedBox(width: 4),
                          Expanded(child: _buildMiniBerthBox(ub2, 'UB', seat.seatNumber == ub2)),
                        ],
                      ),
                    ],
                  ),
                ),
                // Aisle Divider
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  height: 64,
                  width: 20,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Center(
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Text(
                        'AISLE',
                        style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Colors.black38),
                      ),
                    ),
                  ),
                ),
                // Side Berths
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      _buildMiniBerthBox(sl, 'SL (Win)', seat.seatNumber == sl, isWindow: true),
                      const SizedBox(height: 8),
                      _buildMiniBerthBox(su, 'SU', seat.seatNumber == su),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    } else if (is2A) {
      final base = (bay - 1) * 6;
      final lb1 = base + 1;
      final ub1 = base + 2;
      final lb2 = base + 3;
      final ub2 = base + 4;
      final sl = base + 5;
      final su = base + 6;

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'COMPARTMENT BAY $bay (2A)',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Color(0xFF64748B),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _buildMiniBerthBox(lb1, 'LB', seat.seatNumber == lb1, isWindow: true)),
                          const SizedBox(width: 6),
                          Expanded(child: _buildMiniBerthBox(ub1, 'UB', seat.seatNumber == ub1)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _buildMiniBerthBox(lb2, 'LB', seat.seatNumber == lb2, isWindow: true)),
                          const SizedBox(width: 6),
                          Expanded(child: _buildMiniBerthBox(ub2, 'UB', seat.seatNumber == ub2)),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  height: 64,
                  width: 20,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Center(
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Text(
                        'AISLE',
                        style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Colors.black38),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      _buildMiniBerthBox(sl, 'SL', seat.seatNumber == sl, isWindow: true),
                      const SizedBox(height: 8),
                      _buildMiniBerthBox(su, 'SU', seat.seatNumber == su),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Default Chair Car Row
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildMiniBerthBox(seat.seatNumber, seat.isWindow ? 'Window' : 'Seat', true, isWindow: seat.isWindow),
        ],
      ),
    );
  }

  Widget _buildMiniBerthBox(int seatNum, String label, bool isTarget, {bool isWindow = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: isTarget ? const Color(0xFF23695A) : (isWindow ? Colors.blueGrey.shade50 : Colors.grey.shade100),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isTarget ? const Color(0xFF1C5246) : Colors.grey.shade300,
          width: isTarget ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            '$seatNum',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: isTarget ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              color: isTarget ? Colors.white70 : Colors.grey.shade600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
