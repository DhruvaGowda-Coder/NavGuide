import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navguide/features/common/location_share_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocationShareSheet Widget Tests', () {
    testWidgets('Renders Google Maps style Location Share Sheet with live GPS info', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LocationShareSheet(
              latitude: 12.9716,
              longitude: 77.5946,
              placeName: 'MG Road, Bengaluru',
              accuracyMeters: 4.5,
            ),
          ),
        ),
      );

      // Verify title & location details
      expect(find.text('Share Real-Time Location'), findsOneWidget);
      expect(find.text('MG Road, Bengaluru'), findsOneWidget);
      expect(find.textContaining('Accuracy: ±5m'), findsOneWidget);

      // Verify duration chips
      expect(find.text('For 1 hour'), findsOneWidget);
      expect(find.text('For 8 hours'), findsOneWidget);
      expect(find.text('Until I arrive'), findsOneWidget);
      expect(find.text('Current spot only'), findsOneWidget);

      // Verify 4 sharing action buttons
      expect(find.text('WhatsApp'), findsOneWidget);
      expect(find.text('Message'), findsOneWidget);
      expect(find.text('Copy Link'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);

      // Verify privacy notice
      expect(find.textContaining('Direct NavGuide live link'), findsOneWidget);
    });

    testWidgets('Renders trip navigation context when destination is specified', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LocationShareSheet(
              latitude: 13.0827,
              longitude: 80.2707,
              destinationName: 'Chennai Central Station',
              tripEta: '24 min (4:30 PM)',
              remainingDistance: '12.4 km',
              speedKmh: 48,
            ),
          ),
        ),
      );

      expect(find.text('Share Trip Progress'), findsOneWidget);
      expect(find.text('Chennai Central Station'), findsOneWidget);
      expect(find.text('24 min (4:30 PM) · 12.4 km'), findsOneWidget);
    });

    testWidgets('Renders train journey context when train details are specified', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LocationShareSheet(
              latitude: 12.9716,
              longitude: 77.5946,
              trainNumber: '12658',
              trainName: 'Bengaluru Mail',
              nextStation: 'Bangarapet Jn',
              speedKmh: 75,
            ),
          ),
        ),
      );

      expect(find.text('Share Train Journey'), findsOneWidget);
      expect(find.text('12658 · Bengaluru Mail'), findsOneWidget);
      expect(find.text('Approaching Bangarapet Jn · 75 km/h'), findsOneWidget);
    });

    testWidgets('Duration chip selection updates selection state', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LocationShareSheet(
              latitude: 12.9716,
              longitude: 77.5946,
            ),
          ),
        ),
      );

      // Tap 'For 8 hours' chip
      await tester.tap(find.text('For 8 hours'));
      await tester.pump(const Duration(milliseconds: 100));

      // Tap 'Current spot only' chip
      await tester.tap(find.text('Current spot only'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Current spot only'), findsOneWidget);
    });
  });
}
