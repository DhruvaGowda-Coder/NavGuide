import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'app/navguardian_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Keep memory footprint lean (<60MB) and prevent unbounded bitmap bloating
  PaintingBinding.instance.imageCache.maximumSizeBytes = 35 << 20; // 35 MB max
  PaintingBinding.instance.imageCache.maximumSize = 80;

  // Set orientations non-blocking so first frame renders immediately
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const ProviderScope(child: NavGuardianApp()));
}
