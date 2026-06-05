import 'package:flutter_test/flutter_test.dart';
import 'package:microstock_metadata_desktop/main.dart';

void main() {
  testWidgets('Microstock app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MicrostockApp());

    expect(find.text('Microstock Metadata AI'), findsOneWidget);
    expect(find.text('Import JPG, PNG, atau WEBP.'), findsOneWidget);
  });
}
