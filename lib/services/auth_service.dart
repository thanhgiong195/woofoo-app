import '../config/api_config.dart';
import 'api_client.dart';
import 'token_storage.dart';

class AuthService {
  final _api = ApiClient.instance;

  /// Đăng nhập bằng số điện thoại + mật khẩu. Lưu access_token khi thành công.
  Future<void> login(String phone, String password) async {
    final data = await _api.request(
      'POST',
      ApiConfig.login,
      data: {'phone': phone, 'password': password},
    );
    final token = data?['access_token'] as String?;
    if (token == null) {
      throw ApiException('Phản hồi đăng nhập không hợp lệ.');
    }
    await TokenStorage.save(token);
  }

  /// Lấy thông tin người dùng hiện tại (dùng để khôi phục phiên khi mở app).
  Future<Map<String, dynamic>?> me() async {
    final data = await _api.request('GET', ApiConfig.me);
    return data is Map<String, dynamic> ? data : null;
  }

  /// Cập nhật thông tin tài khoản: tên (bắt buộc), email và avatar (tuỳ chọn).
  /// [avatar] là file_path (S3 key) trả về từ [UploadService], không phải URL.
  /// Chỉ gửi các trường được truyền (khác null) để tránh ghi đè giá trị cũ.
  /// Trả về thông tin người dùng đã cập nhật nếu API trả về.
  Future<Map<String, dynamic>?> updateProfile({
    required String name,
    String? email,
    String? avatar,
  }) async {
    final data = await _api.request(
      'POST',
      ApiConfig.updateProfile,
      data: {
        'name': name,
        if (email != null) 'email': email,
        if (avatar != null) 'avatar': avatar,
      },
    );
    return data is Map<String, dynamic> ? data : null;
  }

  Future<void> logout() async {
    try {
      await _api.request('POST', ApiConfig.logout);
    } catch (_) {
      // Bỏ qua lỗi mạng khi logout — vẫn xoá token cục bộ.
    }
    await TokenStorage.clear();
  }
}
