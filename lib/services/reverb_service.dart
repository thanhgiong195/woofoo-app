import 'dart:async';
import 'dart:convert';

import 'package:dart_pusher_channels/dart_pusher_channels.dart';
import 'package:flutter/foundation.dart';

import '../config/api_config.dart';
import '../models/chat.dart';
import '../models/post_comment.dart';
import 'token_storage.dart';

/// FILE MẪU (demo) — hướng dẫn cách nhận dữ liệu realtime từ Laravel Reverb.
///
/// Reverb là server WebSocket của Laravel, nói "giao thức Pusher", nên ở Flutter
/// ta dùng package `dart_pusher_channels` để kết nối. Tư tưởng giống echo.ts bên
/// web: mở 1 kết nối WebSocket tới Reverb, "subscribe" (đăng ký nghe) một kênh,
/// rồi mỗi khi server bắn event lên kênh đó thì ta nhận được dữ liệu.
///
/// Luồng tổng quát (đọc kỹ phần này là hiểu cả file):
///   1. Lấy JWT token đã lưu (để chứng minh "tôi là ai" khi vào kênh private).
///   2. Mở kết nối WebSocket tới Reverb bằng host/port/key do API trả về.
///   3. Đăng ký 1 kênh PRIVATE (vd: `private-chat.5`). Kênh private bắt buộc phải
///      "xin phép" qua API `/api/v1/broadcasting/auth` — gửi kèm token; API kiểm
///      tra user có quyền vào kênh không rồi mới cho nghe.
///   4. `bind('<tên event>')` để lắng nghe đúng loại event ta quan tâm; mỗi event
///      tới sẽ chứa JSON payload — ta parse thành model rồi gọi callback trả ra UI.
///   5. Khi rời màn hình, nhớ gọi [disconnect] để đóng kết nối, tránh rò rỉ.
///
/// LƯU Ý cho người làm theo: mỗi instance ReverbService chỉ quản lý MỘT kết nối.
/// Mỗi màn hình realtime nên tạo riêng 1 instance và tự `disconnect()` ở dispose.
class ReverbService {
  // Kết nối WebSocket hiện tại (null khi chưa/đã ngắt kết nối).
  PusherChannelsClient? _client;
  // Danh sách các "listener" đang mở; giữ lại để hủy hết khi disconnect.
  final List<StreamSubscription> _subs = [];

  /// VÍ DỤ 1: nghe tin nhắn mới của một cuộc trò chuyện chat.
  ///
  /// [settings]  cấu hình Reverb (key/host/port/scheme) do API trả về.
  /// [onMessage] được gọi mỗi khi có tin nhắn mới (event `message.sent`).
  Future<void> subscribeConversation({
    required ReverbSettings settings,
    required int conversationId,
    required void Function(ChatMessage message) onMessage,
  }) async {
    // (1) Token để xác thực khi xin vào kênh private.
    final token = await TokenStorage.read();

    // Khi chạy debug, bật log của package để dễ soi quá trình kết nối WS.
    if (kDebugMode) {
      PusherChannelsPackageLogger.enableLogs();
    }

    // (2) Tạo client WebSocket. options được tính ở _resolveOptions().
    final options = _resolveOptions(settings);
    debugPrint('[Reverb] connecting to ${options.uri}');

    final client = PusherChannelsClient.websocket(
      options: options,
      // Mất kết nối thì gọi refresh() để package tự thử kết nối lại.
      connectionErrorHandler: (exception, trace, refresh) {
        debugPrint('[Reverb] connection error: $exception');
        refresh();
      },
    );
    _client = client;

    // (3) Đăng ký kênh private. Tên kênh phía client luôn có tiền tố "private-".
    // authorizationDelegate = cách package "xin phép" vào kênh: nó sẽ POST tới
    // authEndpoint kèm Authorization header; API trả OK thì mới được nghe.
    final channelName = 'private-chat.$conversationId';
    final channel = client.privateChannel(
      channelName,
      authorizationDelegate:
          EndpointAuthorizableChannelTokenAuthorizationDelegate.forPrivateChannel(
        authorizationEndpoint:
            Uri.parse('${ApiConfig.baseUrl}${settings.authEndpoint}'),
        headers: {
          'Authorization': 'Bearer ${token ?? ''}',
          'Accept': 'application/json',
        },
      ),
    );

    // (4) Lắng nghe event 'message.sent' — tên này phải khớp broadcastAs() ở API.
    _subs.add(channel.bind('message.sent').listen((event) {
      debugPrint('[Reverb] message.sent received: ${event.data}');
      try {
        // event.data đôi khi là chuỗi JSON, đôi khi đã là Map (tùy phiên bản
        // package). Xử lý cả hai trường hợp để không bỏ sót dữ liệu.
        final raw = event.data;
        final Map<String, dynamic> payload = raw is String
            ? jsonDecode(raw) as Map<String, dynamic>
            : Map<String, dynamic>.from(raw as Map);
        // API gửi dạng {conversation_id, message:{...}}; lấy phần "message".
        // Nếu payload phẳng (không bọc) thì dùng luôn payload làm fallback.
        final msg = payload['message'] is Map ? payload['message'] : payload;
        // Parse JSON -> model rồi đẩy ra ngoài cho UI tự cập nhật danh sách.
        onMessage(ChatMessage.fromJson(Map<String, dynamic>.from(msg as Map)));
      } catch (e) {
        // Parse lỗi thì chỉ log, KHÔNG để văng exception làm rớt kết nối.
        debugPrint('[Reverb] parse error: $e');
      }
    }));

    // Các listener phụ dưới đây chỉ để LOG trạng thái — tiện theo dõi khi debug.
    _subs.add(channel.whenSubscriptionSucceeded().listen((_) {
      debugPrint('[Reverb] subscribed to $channelName');
    }));

    _subs.add(channel.onAuthenticationSubscriptionFailed().listen((event) {
      // Vào kênh thất bại — thường do: token hết hạn, user không có quyền vào
      // kênh, hoặc authEndpoint cấu hình sai.
      debugPrint('[Reverb] auth/subscription FAILED for $channelName: ${event.data}');
    }));

    _subs.add(client.lifecycleStream.listen((state) {
      debugPrint('[Reverb] state: $state');
    }));

    // Mỗi lần (kết nối lại) thành công thì đăng ký kênh lại — nhờ vậy app vẫn
    // nhận được dữ liệu sau khi mạng chập chờn rồi nối lại.
    _subs.add(client.onConnectionEstablished.listen((_) {
      debugPrint('[Reverb] connection established → subscribing');
      channel.subscribeIfNotUnsubscribed();
    }));

    // (Bắt đầu) Mở kết nối. Các listener ở trên đã gắn sẵn nên không bỏ lỡ event.
    await client.connect();
  }

  /// VÍ DỤ 2: nghe bình luận mới của một bài viết.
  ///
  /// Cấu trúc HỆT VÍ DỤ 1, chỉ khác 3 chỗ: tên kênh (`private-post.{id}`), tên
  /// event (`comment.created`), và kiểu model parse ra (`PostComment`). Hãy dùng
  /// hàm này làm khuôn mẫu khi cần thêm một loại dữ liệu realtime mới.
  ///
  /// [onComment] được gọi mỗi khi có bình luận mới.
  Future<void> subscribePost({
    required ReverbSettings settings,
    required int postId,
    required void Function(PostComment comment) onComment,
  }) async {
    // (1) Token xác thực.
    final token = await TokenStorage.read();

    if (kDebugMode) {
      PusherChannelsPackageLogger.enableLogs();
    }

    // (2) Mở client WebSocket.
    final options = _resolveOptions(settings);
    debugPrint('[Reverb] connecting to ${options.uri}');

    final client = PusherChannelsClient.websocket(
      options: options,
      connectionErrorHandler: (exception, trace, refresh) {
        debugPrint('[Reverb] connection error: $exception');
        refresh();
      },
    );
    _client = client;

    // (3) Đăng ký kênh private của riêng bài viết này.
    final channelName = 'private-post.$postId';
    final channel = client.privateChannel(
      channelName,
      authorizationDelegate:
          EndpointAuthorizableChannelTokenAuthorizationDelegate.forPrivateChannel(
        authorizationEndpoint:
            Uri.parse('${ApiConfig.baseUrl}${settings.authEndpoint}'),
        headers: {
          'Authorization': 'Bearer ${token ?? ''}',
          'Accept': 'application/json',
        },
      ),
    );

    // (4) Lắng nghe 'comment.created' và parse payload thành PostComment.
    _subs.add(channel.bind('comment.created').listen((event) {
      debugPrint('[Reverb] comment.created received: ${event.data}');
      try {
        final raw = event.data;
        final Map<String, dynamic> payload = raw is String
            ? jsonDecode(raw) as Map<String, dynamic>
            : Map<String, dynamic>.from(raw as Map);
        // API gửi dạng {comment:{...}}; lấy phần "comment" (fallback nếu phẳng).
        final c = payload['comment'] is Map ? payload['comment'] : payload;
        onComment(PostComment.fromJson(Map<String, dynamic>.from(c as Map)));
      } catch (e) {
        debugPrint('[Reverb] parse error: $e');
      }
    }));

    // Listener log trạng thái (giống ví dụ 1).
    _subs.add(channel.whenSubscriptionSucceeded().listen((_) {
      debugPrint('[Reverb] subscribed to $channelName');
    }));

    _subs.add(channel.onAuthenticationSubscriptionFailed().listen((event) {
      debugPrint('[Reverb] auth/subscription FAILED for $channelName: ${event.data}');
    }));

    _subs.add(client.lifecycleStream.listen((state) {
      debugPrint('[Reverb] state: $state');
    }));

    _subs.add(client.onConnectionEstablished.listen((_) {
      debugPrint('[Reverb] connection established → subscribing');
      channel.subscribeIfNotUnsubscribed();
    }));

    await client.connect();
  }

  /// Tính thông số kết nối WS từ cấu hình Reverb do API trả về:
  /// dùng đúng host/port/key, chọn wss nếu API chạy https (useTLS).
  PusherChannelsOptions _resolveOptions(ReverbSettings settings) {
    return PusherChannelsOptions.fromHost(
      scheme: settings.useTLS ? 'wss' : 'ws',
      host: settings.host,
      port: settings.port,
      key: settings.key,
    );
  }

  /// Đóng kết nối và hủy mọi listener. BẮT BUỘC gọi ở dispose() của màn hình để
  /// tránh rò rỉ bộ nhớ và giữ kết nối WebSocket thừa.
  void disconnect() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _client?.dispose();
    _client = null;
  }
}
