import 'package:flutter_test/flutter_test.dart';
import 'package:biscuit_protector/main.dart';

void main() {
  testWidgets('Biscuit Protector app loads', (WidgetTester tester) async {
    await tester.pumpWidget(const BiscuitProtectorApp());

    expect(find.text('Biscuit Protector'), findsOneWidget);
    expect(find.text('ESP32 Connection'), findsOneWidget);
    expect(find.text('Distance'), findsOneWidget);
    expect(find.text('Temperature'), findsOneWidget);
    expect(find.text('Humidity'), findsOneWidget);
  });
}