import '../config/api_config.dart';
import '../models/chat.dart';
import 'api_client.dart';

class ChatService {
  final _api = ApiClient.instance;

  /// Danh sách cuộc trò chuyện (phân trang).
  Future<List<Conversation>> conversations({int page = 1, int perPage = 20}) async {
    final data = await _api.request(
      'GET',
      ApiConfig.conversations,
      query: {'page': page, 'per_page': perPage},
    );
    final list = (data is Map<String, dynamic> ? data['list'] : data) as List?;
    return list
            ?.whereType<Map<String, dynamic>>()
            .map(Conversation.fromJson)
            .toList() ??
        const [];
  }

  /// Mở (hoặc lấy lại) cuộc trò chuyện 1-1 với người dùng [userId].
  Future<Conversation> openConversation(int userId) async {
    final data = await _api.request(
      'POST',
      ApiConfig.conversations,
      data: {'user_id': userId},
    );
    return Conversation.fromJson(data as Map<String, dynamic>);
  }

  /// Chi tiết 1 cuộc trò chuyện — kèm cấu hình `reverb` để kết nối realtime.
  Future<Conversation> show(int id) async {
    final data = await _api.request('GET', ApiConfig.conversation(id));
    return Conversation.fromJson(data as Map<String, dynamic>);
  }

  /// Lịch sử tin nhắn (phân trang, mới nhất trước).
  Future<List<ChatMessage>> messages(int id, {int page = 1, int perPage = 30}) async {
    final data = await _api.request(
      'GET',
      ApiConfig.messages(id),
      query: {'page': page, 'per_page': perPage},
    );
    final list = (data is Map<String, dynamic> ? data['list'] : data) as List?;
    return list
            ?.whereType<Map<String, dynamic>>()
            .map(ChatMessage.fromJson)
            .toList() ??
        const [];
  }

  /// Gửi tin nhắn — văn bản và/hoặc danh sách file đính kèm.
  /// Mỗi attachment: {type, path, name?, mime?, size?}.
  Future<ChatMessage> sendMessage(
    int id, {
    String body = '',
    List<Map<String, dynamic>> attachments = const [],
  }) async {
    final data = await _api.request(
      'POST',
      ApiConfig.messages(id),
      data: {
        if (body.isNotEmpty) 'body': body,
        if (attachments.isNotEmpty) 'attachments': attachments,
      },
    );
    return ChatMessage.fromJson(data as Map<String, dynamic>);
  }

  /// Đánh dấu đã đọc tới [lastReadMessageId].
  Future<void> markRead(int id, int lastReadMessageId) async {
    await _api.request(
      'POST',
      ApiConfig.markRead(id),
      data: {'last_read_message_id': lastReadMessageId},
    );
  }
}
