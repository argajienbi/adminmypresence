import 'package:flutter_test/flutter_test.dart';

import 'package:adminmypresence/app.dart';

void main() {
  testWidgets('App renders', (WidgetTester tester) async {
    await tester.pumpWidget(const AdminMyPresenceApp());

    expect(find.text('Admin MyPresence'), findsOneWidget);
  });
}
