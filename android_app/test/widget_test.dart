import 'package:flutter_test/flutter_test.dart';

import 'package:cursor_controller/main.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const CursorControllerApp());
    await tester.pump();

    // The app should show either the onboarding settings screen (when
    // disconnected) or the chat screen title.
    expect(find.textContaining('Connect'), findsWidgets);
  });
}
