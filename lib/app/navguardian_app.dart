import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import '../features/home/home_screen.dart';
import '../features/crowdsourcing/community_hazards_screen.dart';
import '../features/journey/journey_history_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/unions/unions_screen.dart';
import '../features/unions/global_emergency_banner.dart';
import '../features/nearby/nearby_places_screen.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class NavGuardianApp extends StatelessWidget {
  const NavGuardianApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: appNavigatorKey,
    title: 'NavGuide',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xfff7f9f6),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff23695a)),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xfff7f9f6)),
    ),
    builder: (context, child) {
      return Stack(
        children: [
          if (child != null) child,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GlobalConvoyEmergencyBanner(navigatorKey: appNavigatorKey),
          ),
        ],
      );
    },
    home: const _AppShell(),
  );
}

class _AppShell extends ConsumerStatefulWidget {
  const _AppShell();
  @override
  ConsumerState<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<_AppShell>
    with WidgetsBindingObserver {
  int _index = 0;
  bool _onboarded = true;

  // ── Lazy-but-stable tab cache ──────────────────────────────────────────
  // Tabs are created on FIRST visit and cached forever after.
  // This avoids rebuilding screens on tab switch (stable object identity),
  // while also avoiding the 172-frame startup spike that happens when all
  // 4 heavy screens (especially GoogleMap) initialize simultaneously.
  final Map<int, Widget> _tabCache = {};

  static const _tabBuilders = <int, Widget Function()>{
    0: HomeScreen.new,
    1: UnionsScreen.new,
    2: NearbyPlacesScreen.new,
  };

  Widget _getTab(int index) =>
      _tabCache.putIfAbsent(index, () => _tabBuilders[index]!());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Only pre-build tab 0 (HomeScreen) at startup
    _tabCache[0] = const HomeScreen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref
        .read(foregroundProvider.notifier)
        .setActive(state == AppLifecycleState.resumed);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/navguide_icon.png',
              width: 32,
              height: 32,
              cacheWidth: 96, // decode at display size (3× max)
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'NavGuide',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.2),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.science_outlined),
          tooltip: 'Journeys & AI',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const JourneyHistoryScreen()),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.warning_amber_rounded),
          tooltip: 'Hazards',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CommunityHazardsScreen()),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Settings',
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
        ),
        const SizedBox(width: 4),
      ],
    ),
    body: SafeArea(
      child: !_onboarded
          ? Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset(
                          'assets/navguide_logo.png',
                          width: 160,
                          height: 160,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Find your footing.',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Live location. Clear device signals.\nA foundation for more informed journeys.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Location access is optional and requested when you enable it. No journey data is saved. AI and safer-route recommendations are planned.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () => setState(() => _onboarded = true),
                        child: const Text('Get started'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : IndexedStack(
              index: _index,
              children: List.generate(
                3,
                (i) => _getTab(i), // lazy-created on first visit, cached forever
              ),
            ),
    ),
    bottomNavigationBar: !_onboarded
        ? null
        : NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.explore_outlined),
                selectedIcon: Icon(Icons.explore),
                label: 'Explore',
              ),
              NavigationDestination(
                icon: Icon(Icons.group_outlined),
                selectedIcon: Icon(Icons.group),
                label: 'Unions',
              ),
              NavigationDestination(
                icon: Icon(Icons.near_me_outlined),
                selectedIcon: Icon(Icons.near_me_rounded),
                label: 'Near Me',
              ),
            ],
          ),
  );
}
