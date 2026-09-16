import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import '../features/home/home_screen.dart';
import '../features/sensors/sensor_debug_screen.dart';
import '../features/roadmap/roadmap_screen.dart';
import '../features/settings/settings_screen.dart';

class NavGuardianApp extends StatelessWidget {
  const NavGuardianApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'NavGuardian AI',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xfff7f9f6),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff23695a)),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xfff7f9f6)),
    ),
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
  bool _onboarded = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      title: const Row(
        children: [
          Icon(Icons.explore),
          SizedBox(width: 10),
          Text('NavGuardian', style: TextStyle(fontWeight: FontWeight.w700)),
          SizedBox(width: 6),
          Text('AI', style: TextStyle(fontSize: 14)),
        ],
      ),
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
                      const Icon(
                        Icons.explore_outlined,
                        size: 88,
                        color: Color(0xff23695a),
                      ),
                      const SizedBox(height: 24),
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