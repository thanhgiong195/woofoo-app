import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';
import '../services/token_storage.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  final _service = AuthService();

  AuthStatus _status = AuthStatus.unknown;
  Map<String, dynamic>? _user;

  AuthStatus get status => _status;
  Map<String, dynamic>? get user => _user;

  /// Khôi phục phiên khi mở app: nếu có token thì xác thực qua /me.
  Future<void> bootstrap() async {
    final token = await TokenStorage.read();
    if (token == null) {
      _set(AuthStatus.unauthenticated);
      return;
    }
    try {
      _user = await _service.me();
      _set(AuthStatus.authenticated);
    } catch (_) {
      await TokenStorage.clear();
      _set(AuthStatus.unauthenticated);
    }
  }

  Future<void> login(String phone, String password) async {
    await _service.login(phone, password);
    try {
      _user = await _service.me();
    } catch (_) {
      _user = null;
    }
    _set(AuthStatus.authenticated);
  }

  Future<void> logout() async {
    await _service.logout();
    _user = null;
    _set(AuthStatus.unauthenticated);
  }

  void _set(AuthStatus s) {
    _status = s;
    notifyListeners();
  }
}
