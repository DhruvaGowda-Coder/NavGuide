import 'package:flutter/material.dart';
import '../safety_data/route_safety_inspection_screen.dart';
import '../safety_scoring/route_safety_recommendation_screen.dart';

class DestinationSearchScreen extends StatefulWidget {
  const DestinationSearchScreen({super.key});

  @override
  State<DestinationSearchScreen> createState() => _DestinationSearchScreenState();
}

class _DestinationSearchScreenState extends State<DestinationSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  final List<String> _quickChips = [
    'Silk Board',
    'Electronic City',
    'Whitefield',
    'Hebbal',
    'Koramangala',
    'MG Road',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    // Filter corridors according to search query
    final filteredIndices = <int>[];
    for (var i = 0; i < kBangaloreRoutePresets.length; i++) {
      final p = kBangaloreRoutePresets[i];
      if (_query.isEmpty) {
        filteredIndices.add(i);
      } else {
        final q = _query.toLowerCase();
        final matches = p.title.toLowerCase().contains(q) ||
            p.subtitle.toLowerCase().contains(q) ||
            p.originName.toLowerCase().contains(q) ||
            p.destName.toLowerCase().contains(q);
        if (matches) filteredIndices.add(i);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Destination Search & Routes'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomInset),
        children: [
          TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _query = val.trim()),
            decoration: InputDecoration(
              labelText: 'Where would you like to go?',
              hintText: 'e.g. Electronic City, Whitefield, Hebbal',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),
          const SizedBox(height: 10),

          // Quick Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ActionChip(
                  label: const Text('All Corridors', style: TextStyle(fontSize: 11)),
                  avatar: const Icon(Icons.route, size: 14),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
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
                        setState(() => _query = chip);
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Phase 7 AI Safest-Route Recommendation Banner
          Card(
            elevation: 3,
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
                        child: const Icon(Icons.auto_awesome,
                            color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Phase 7: Safest-Route AI Engine',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xff23695a),
                              ),
                            ),
                            Text(
                              '6D Risk Scoring • Peak-Hazard Penalty • Multi-Objective Ranking',
                              style: TextStyle(fontSize: 10, color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Evaluates candidate routes balancing safety vs. travel time in Safest, Balanced, or Fastest modes. Identifies critical hazards and explains why a route is recommended.',
                    style: TextStyle(fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xff23695a),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () {
                        final targetIdx = filteredIndices.isNotEmpty ? filteredIndices.first : 0;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RouteSafetyRecommendationScreen(
                              initialPresetIndex: targetIdx,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.shield_outlined, size: 18),
                      label: const Text('Open Safest-Route AI Engine'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Bangalore Safety Corridors',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              Text(
                '${filteredIndices.length} available',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (filteredIndices.isEmpty)
            Card(
              elevation: 0,
              color: Colors.grey.shade100,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.search_off, size: 40, color: Colors.grey.shade500),
                    const SizedBox(height: 8),
                    Text(
                      'No corridors matching "$_query"',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Try searching Silk Board, Hebbal, Whitefield, or Electronic City.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      child: const Text('View All Corridors'),
                    ),
                  ],
                ),
              ),
            )
          else
            for (final i in filteredIndices) ...[
              Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        const Color(0xff23695a).withValues(alpha: 0.1),
                    child:
                        const Icon(Icons.route_outlined, color: Color(0xff23695a)),
                  ),
                  title: Text(
                    kBangaloreRoutePresets[i].title,
                    style:
                        const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  subtitle: Text(
                    kBangaloreRoutePresets[i].subtitle,
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Raw Safety Data (Phase 6)',
                        icon: const Icon(Icons.data_usage, size: 18, color: Colors.black45),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RouteSafetyInspectionScreen(
                                initialPresetIndex: i,
                              ),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        tooltip: 'Safest-Route AI (Phase 7)',
                        icon: const Icon(Icons.security, size: 18, color: Color(0xff23695a)),
                        onPressed: () {
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
                    ],
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
