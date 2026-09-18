import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../device/railway/train_tracking_engine.dart';

class StationPickerSheet extends StatefulWidget {
  final String title;
  final TrainTrackingEngine engine;
  final String? currentSelectedCode;

  const StationPickerSheet({
    super.key,
    required this.title,
    required this.engine,
    this.currentSelectedCode,
  });

  static Future<RailwayStation?> show({
    required BuildContext context,
    required String title,
    required TrainTrackingEngine engine,
    String? currentSelectedCode,
  }) {
    return showModalBottomSheet<RailwayStation>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StationPickerSheet(
        title: title,
        engine: engine,
        currentSelectedCode: currentSelectedCode,
      ),
    );
  }

  @override
  State<StationPickerSheet> createState() => _StationPickerSheetState();
}

class _StationPickerSheetState extends State<StationPickerSheet> {
  static const primaryEmerald = Color(0xff23695a);
  static const scaffoldBg = Color(0xfff7f9f6);
  static const cardBg = Colors.white;
  static const textDark = Color(0xff191c1b);
  static const textMuted = Color(0xff53645c);

  final TextEditingController _searchController = TextEditingController();
  List<RailwayStation> _filtered = [];

  final List<String> _popularCodes = [
    'SBC', 'MAS', 'NDLS', 'MMCT', 'HWH', 'CSMT', 'SC', 'PUNE', 'MYS', 'ADI', 'BSB', 'GHY', 'TVC'
  ];

  @override
  void initState() {
    super.initState();
    _filtered = widget.engine.searchStations('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    setState(() {
      _filtered = widget.engine.searchStations(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomInset + keyboardInset),
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
              Text(
                widget.title,
                style: const TextStyle(
                  color: textDark,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: scaffoldBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearch,
                  autofocus: false,
                  style: const TextStyle(color: textDark, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search by station name or code (e.g. SBC, NDLS)',
                    hintStyle: const TextStyle(color: textMuted, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, color: primaryEmerald),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18, color: textMuted),
                            onPressed: () {
                              _searchController.clear();
                              _onSearch('');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _popularCodes.map((code) {
                    final station = widget.engine.getStationByCode(code);
                    if (station == null) return const SizedBox.shrink();
                    final isSelected = widget.currentSelectedCode == code;

                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(
                          '${station.code} • ${station.city}',
                          style: TextStyle(
                            color: isSelected ? Colors.white : primaryEmerald,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        backgroundColor: isSelected
                            ? primaryEmerald
                            : primaryEmerald.withValues(alpha: 0.08),
                        side: BorderSide(
                          color: isSelected ? primaryEmerald : primaryEmerald.withValues(alpha: 0.2),
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          Navigator.pop(context, station);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'No stations found',
                          style: TextStyle(color: textMuted, fontSize: 13),
                        ),
                      )
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => Divider(
                          color: Colors.black.withValues(alpha: 0.05),
                          height: 1,
                        ),
                        itemBuilder: (ctx, index) {
                          final st = _filtered[index];
                          final isSelected = widget.currentSelectedCode == st.code;

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? primaryEmerald.withValues(alpha: 0.15)
                                    : scaffoldBg,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.train_outlined,
                                color: isSelected ? primaryEmerald : textMuted,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              st.name,
                              style: TextStyle(
                                color: isSelected ? primaryEmerald : textDark,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              '${st.city}, ${st.state} • ${st.zone} Zone',
                              style: const TextStyle(color: textMuted, fontSize: 12),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? primaryEmerald
                                    : primaryEmerald.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                st.code,
                                style: TextStyle(
                                  color: isSelected ? Colors.white : primaryEmerald,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            onTap: () {
                              HapticFeedback.lightImpact();
                              Navigator.pop(context, st);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
