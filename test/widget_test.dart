import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:woofoo_app/screens/login_screen.dart';

void main() {
  testWidgets('Màn hình đăng nhập hiển thị các trường cần thiết',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Số điện thoại'), findsOneWidget);
    expect(find.text('Mật khẩu'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Đăng nhập'), findsOneWidget);
  });
}
