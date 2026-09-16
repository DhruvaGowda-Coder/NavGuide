import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navguardian_ai/app/navguardian_app.dart';
import 'package:navguardian_ai/app/providers.dart';

void main() {
  testWidgets('onboarding opens honest unconfigured map state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectivityProvider.overrideWith((ref) => Stream.value(false)),
        ],
        child: const NavGuardianApp(),
      ),
    );
    expect(find.text('Find your footing.'), findsOneWidget);
    await tester.tap(find.text('Get started'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Your map starts here'), findsOneWidget);
    expect(find.text('Enable live location'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
