import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/app/app.dart';

void main() {
  testWidgets('TranslatorApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: TranslatorApp()));
    expect(find.text('AI Video Translator'), findsOneWidget);
  });
}
