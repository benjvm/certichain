import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app/app.dart';

void main() {
  testWidgets('CertiChain app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const CertiChainApp());

    expect(find.text('CertiChain'), findsOneWidget);
  });
}
