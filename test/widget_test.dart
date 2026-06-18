import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:hiddenly/auth_gate.dart';

void main() {
  testWidgets('App loads without crash', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: AuthGate(),
    ));

    await tester.pump();

    expect(find.byType(AuthGate), findsOneWidget);
  });
}
