import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  // Đọc từ .env lúc chạy (đã load trong main). Fallback khi thiếu biến.
  static String get baseUrl => dotenv.env['API_URI'] ?? 'http://localhost:8080';

  static const String apiPrefix = '/api/v1/app';

  // Common
  static const String presignedUrl = '/api/v1/presigned-url';

  // Auth
  static const String login = '$apiPrefix/auth/login';
  static const String me = '$apiPrefix/auth/me';
  static const String logout = '$apiPrefix/auth/logout';
  static const String updateProfile = '$apiPrefix/auth/update-profile';

  // Posts
  static const String posts = '$apiPrefix/posts';
  static String post(int id) => '$apiPrefix/posts/$id';
  static String postComments(int id) => '$apiPrefix/posts/$id/comments';

  // Chat
  static const String conversations = '$apiPrefix/chat/conversations';
  static String conversation(int id) => '$apiPrefix/chat/conversations/$id';
  static String messages(int id) =>
      '$apiPrefix/chat/conversations/$id/messages';
  static String markRead(int id) => '$apiPrefix/chat/conversations/$id/read';
}
