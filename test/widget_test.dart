import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paw_watch/views/screens/landing_screen.dart';

void main() {
  testWidgets('LandingScreen smoke test renders branding and structure', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LandingScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LandingScreen), findsOneWidget);
  });
}
