import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../services/chat_service.dart';
import '../services/reverb_service.dart';
import '../services/upload_service.dart';
import '../widgets/post_image_view.dart';

/// File đã upload lên S3, đang chờ gửi kèm tin nhắn.
class _PendingAttachment {
  final String type; // image | file
  final String path; // S3 key
  final String mime;
  final String name;
  final int size;

  _PendingAttachment({
    required this.type,
    required this.path,
    required this.mime,
    required this.name,
    required this.size,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'path': path,
    'name': name,
    'mime': mime,
    'size': size,
  };
}

class ChatDetailScreen extends StatefulWidget {
  final int conversationId;
  final String title;

  const ChatDetailScreen({
    super.key,
    required this.conversationId,
    required this.title,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _service = ChatService();
  final _reverb = ReverbService();
  final _uploader = UploadService();
  final _inputCtrl = TextEditingController();
  final _scrollController = ScrollController();

  // Số tin mỗi lần tải (phải khớp perPage gửi lên API để biết khi nào hết trang).
  static const _pageSize = 30;

  // Giữ theo thứ tự mới nhất trước (index 0 = mới nhất). ListView reverse=true
  // sẽ hiển thị tin mới nhất ở dưới cùng.
  final List<ChatMessage> _messages = [];
  final List<_PendingAttachment> _pending = [];
  bool _loading = true;
  bool _sending = false;
  bool _uploading = false;
  bool _loadingMore = false; // đang tải thêm tin cũ
  bool _hasMore = true; // còn tin cũ hơn để tải không
  String? _error;

  int? get _myId => context.read<AuthProvider>().user?['id'] as int?;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _bootstrap();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _reverb.disconnect();
    _inputCtrl.dispose();
    super.dispose();
  }

  // ListView reverse=true: offset 0 = đáy (tin mới nhất), maxScrollExtent = đỉnh
  // (tin cũ nhất). Vuốt lên xem tin cũ tức là tiến gần maxScrollExtent → tải thêm.
  void _onScroll() {
    if (_loadingMore || !_hasMore || !_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _messages.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      // _messages giữ mới→cũ, nên tin cũ nhất hiện có nằm ở cuối list.
      final oldestId = _messages.last.id;
      final older = await _service.messages(
        widget.conversationId,
        perPage: _pageSize,
        beforeId: oldestId,
      );
      if (!mounted) return;
      setState(() {
        // Trả về ít hơn 1 trang nghĩa là đã chạm tin đầu tiên → hết.
        if (older.length < _pageSize) _hasMore = false;
        // older: cũ→mới (ascending). Đảo thành mới→cũ rồi nối vào CUỐI (sau tin
        // cũ nhất hiện tại), bỏ qua id đã có để chống trùng.
        final existing = _messages.map((m) => m.id).toSet();
        _messages.addAll(older.reversed.where((m) => !existing.contains(m.id)));
      });
    } catch (_) {
      // Im lặng: lần vuốt sau sẽ thử lại (không đổi _hasMore).
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _bootstrap() async {
    try {
      // show() trả về cấu hình reverb để kết nối realtime.
      final convo = await _service.show(widget.conversationId);
      final history = await _service.messages(widget.conversationId);

      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(history);
        _loading = false;
      });

      _markReadLatest();

      final reverb = convo.reverb;
      if (reverb != null && reverb.key.isNotEmpty) {
        await _reverb.subscribeConversation(
          settings: reverb,
          conversationId: widget.conversationId,
          onMessage: _onRealtimeMessage,
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Không tải được cuộc trò chuyện';
        });
      }
    }
  }

  void _onRealtimeMessage(ChatMessage message) {
    if (!mounted) return;
    if (!_addMessage(message)) return;
    if (message.senderUserId != _myId) _markReadLatest();
  }

  /// Thêm tin vào đầu danh sách nếu chưa có (chống trùng theo id giữa luồng
  /// HTTP gửi tin và event realtime phát lại). Trả về true nếu đã thêm.
  bool _addMessage(ChatMessage message) {
    if (_messages.any((m) => m.id == message.id)) return false;
    setState(() => _messages.insert(0, message));
    return true;
  }

  void _markReadLatest() {
    if (_messages.isEmpty) return;
    _service
        .markRead(widget.conversationId, _messages.first.id)
        .catchError((_) {});
  }

  Future<void> _pickAttachment(String category) async {
    final isImage = category == 'image';
    // image → jpg/png; file → pdf/doc/docx (theo ràng buộc API).
    final allowed = isImage ? ['jpg', 'jpeg', 'png'] : ['pdf', 'doc', 'docx'];

    // Ảnh phải mở qua thư viện ảnh (FileType.image); tài liệu mở qua trình
    // duyệt Files (FileType.custom). iOS không cho custom + FileType.image.
    final result = await FilePicker.platform.pickFiles(
      type: isImage ? FileType.image : FileType.custom,
      allowedExtensions: isImage ? null : allowed,
      withData: true,
    );
    final file = result?.files.firstOrNull;
    if (file == null || file.bytes == null) return;

    final ext = (file.extension ?? '').toLowerCase();
    if (!allowed.contains(ext)) {
      _toast(
        isImage
            ? 'Vui lòng chọn ảnh định dạng JPG hoặc PNG'
            : 'Định dạng không được hỗ trợ',
      );
      return;
    }
    // content_type key API chấp nhận: jpeg phải gửi 'jpg'.
    final contentTypeKey = ext == 'jpeg' ? 'jpg' : ext;

    setState(() => _uploading = true);
    try {
      final uploaded = await _uploader.upload(
        bytes: file.bytes!,
        filename: file.name,
        prefix: 'chat',
        contentTypeKey: contentTypeKey,
      );
      if (!mounted) return;
      setState(() {
        _pending.add(
          _PendingAttachment(
            type: category,
            path: uploaded.path,
            mime: uploaded.mime,
            name: file.name,
            size: file.size,
          ),
        );
      });
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Tải tệp lên thất bại');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if ((text.isEmpty && _pending.isEmpty) || _sending) return;
    setState(() => _sending = true);
    try {
      final sent = await _service.sendMessage(
        widget.conversationId,
        body: text,
        attachments: _pending.map((a) => a.toJson()).toList(),
      );
      _inputCtrl.clear();
      if (mounted) {
        setState(() => _pending.clear());
        _addMessage(sent);
      }
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _showAttachSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder:
          (_) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: const Text('Hình ảnh'),
                  subtitle: const Text('JPG, PNG (tối đa 5MB)'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickAttachment('image');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Tài liệu'),
                  subtitle: const Text('PDF, DOC, DOCX (tối đa 20MB)'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickAttachment('file');
                  },
                ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          const Divider(height: 1),
          if (_pending.isNotEmpty || _uploading) _buildPendingStrip(),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_messages.isEmpty) {
      return const Center(child: Text('Hãy bắt đầu cuộc trò chuyện'));
    }
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.all(12),
      // +1 ô ở "đỉnh" (index cuối của list reverse) để hiển thị spinner tải thêm.
      itemCount: _messages.length + (_loadingMore ? 1 : 0),
      itemBuilder: (_, i) {
        if (i >= _messages.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return _MessageBubble(
          message: _messages[i],
          isMine: _messages[i].senderUserId == _myId,
        );
      },
    );
  }

  Widget _buildPendingStrip() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      alignment: Alignment.centerLeft,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (int i = 0; i < _pending.length; i++)
            _PendingChip(
              attachment: _pending[i],
              onRemove: () => setState(() => _pending.removeAt(i)),
            ),
          if (_uploading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Đính kèm',
              onPressed: _uploading ? null : _showAttachSheet,
              icon: const Icon(Icons.attach_file),
            ),
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: 'Nhập tin nhắn...',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              icon:
                  _sending
                      ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingChip extends StatelessWidget {
  final _PendingAttachment attachment;
  final VoidCallback onRemove;

  const _PendingChip({required this.attachment, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Chip(
        avatar: Icon(
          attachment.type == 'image' ? Icons.image : Icons.description,
          size: 18,
        ),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140),
          child: Text(attachment.name, overflow: TextOverflow.ellipsis),
        ),
        onDeleted: onRemove,
        deleteIcon: const Icon(Icons.close, size: 18),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;

  const _MessageBubble({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasBody = (message.body ?? '').isNotEmpty;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        decoration: BoxDecoration(
          color: isMine ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            for (final a in message.attachments)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _AttachmentView(attachment: a),
              ),
            if (hasBody)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  message.body!,
                  style: TextStyle(
                    color: isMine ? scheme.onPrimary : scheme.onSurface,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentView extends StatelessWidget {
  final MessageAttachment attachment;

  const _AttachmentView({required this.attachment});

  @override
  Widget build(BuildContext context) {
    if (attachment.isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 200,
          child: PostImageView(url: attachment.url, height: 160),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file_outlined, size: 22),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              attachment.name ?? 'Tệp đính kèm',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
