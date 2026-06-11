import 'package:flutter_test/flutter_test.dart';

import 'package:smart_helmet/main.dart';

void main() {
  testWidgets('App renders connect screen', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartHelmetApp());
    await tester.pump();

    // Màn hình kết nối hiển thị tiêu đề
    expect(find.text('SMART HELMET'), findsOneWidget);
  });
}
