class UserMini {
  final int id;
  final String? name;
  final String? avatarUrl;

  UserMini({required this.id, this.name, this.avatarUrl});

  factory UserMini.fromJson(Map<String, dynamic> json) => UserMini(
    id: json['id'] as int,
    name: json['name'] as String?,
    avatarUrl: json['avatar_url'] as String?,
  );
}

class MessageAttachment {
  final int id;
  final String type; // image | file
  final String? url;
  final String? name;
  final String? mime;
  final int? size;

  MessageAttachment({
    required this.id,
    required this.type,
    this.url,
    this.name,
    this.mime,
    this.size,
  });

  bool get isImage => type == 'image';

  factory MessageAttachment.fromJson(Map<String, dynamic> json) =>
      MessageAttachment(
        id: (json['id'] as num).toInt(),
        type: json['type']?.toString() ?? 'file',
        url: json['url']?.toString(),
        name: json['name']?.toString(),
        mime: json['mime']?.toString(),
        size: (json['size'] as num?)?.toInt(),
      );
}

class ChatMessage {
  final int id;
  final int conversationId;
  final int senderUserId;
  final String? body;
  final String? createdAt;
  final UserMini? sender;
  final List<MessageAttachment> attachments;

  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderUserId,
    this.body,
    this.createdAt,
    this.sender,
    this.attachments = const [],
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as int,
    conversationId: (json['conversation_id'] as num).toInt(),
    senderUserId: (json['sender_user_id'] as num).toInt(),
    body: json['body'] as String?,
    createdAt: json['created_at']?.toString(),
    sender:
        json['sender'] is Map<String, dynamic>
            ? UserMini.fromJson(json['sender'] as Map<String, dynamic>)
            : null,
    attachments:
        (json['attachments'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(MessageAttachment.fromJson)
            .toList() ??
        const [],
  );
}

class Conversation {
  final int id;
  final int? roomId;
  final int? otherUserId;
  final int unreadCount;
  final String? lastMessageAt;
  final UserMini? otherUser;
  final ChatMessage? latestMessage;
  final ReverbSettings? reverb;

  Conversation({
    required this.id,
    this.roomId,
    this.otherUserId,
    this.unreadCount = 0,
    this.lastMessageAt,
    this.otherUser,
    this.latestMessage,
    this.reverb,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: json['id'] as int,
    roomId: (json['room_id'] as num?)?.toInt(),
    otherUserId: (json['other_user_id'] as num?)?.toInt(),
    unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
    lastMessageAt: json['last_message_at']?.toString(),
    otherUser:
        json['other_user'] is Map<String, dynamic>
            ? UserMini.fromJson(json['other_user'] as Map<String, dynamic>)
            : null,
    latestMessage:
        json['latest_message'] is Map<String, dynamic>
            ? ChatMessage.fromJson(
              json['latest_message'] as Map<String, dynamic>,
            )
            : null,
    reverb:
        json['reverb'] is Map<String, dynamic>
            ? ReverbSettings.fromJson(json['reverb'] as Map<String, dynamic>)
            : null,
  );
}

/// Cấu hình Reverb do API trả về
class ReverbSettings {
  final String key;
  final String host;
  final int port;
  final String scheme;
  final String authEndpoint;

  ReverbSettings({
    required this.key,
    required this.host,
    required this.port,
    required this.scheme,
    required this.authEndpoint,
  });

  bool get useTLS => scheme == 'https';

  factory ReverbSettings.fromJson(Map<String, dynamic> json) => ReverbSettings(
    key: json['key']?.toString() ?? '',
    host: json['host']?.toString() ?? 'localhost',
    port: (json['port'] as num?)?.toInt() ?? 8081,
    scheme: json['scheme']?.toString() ?? 'http',
    authEndpoint:
        json['auth_endpoint']?.toString() ?? '/api/v1/broadcasting/auth',
  );
}
