import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../services/chat_service.dart';
import 'chat_detail_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _service = ChatService();
  late Future<List<Conversation>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.conversations();
  }

  Future<void> _reload() async {
    final future = _service.conversations();
    setState(() {
      _future = future;
    });
    await future;
  }

  void _openConversation(Conversation c) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => ChatDetailScreen(
            conversationId: c.id,
            title: c.otherUser?.name ?? 'Trò chuyện',
          ),
        ))
        .then((_) => _reload());
  }

  Future<void> _showNewConversationDialog() async {
    final created = await showDialog<Conversation>(
      context: context,
      builder: (_) => const NewConversationDialog(),
    );
    if (created != null && mounted) {
      _openConversation(created);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tin nhắn'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Đăng xuất',
            onPressed: () => context.read<AuthProvider>().logout(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_chat',
        onPressed: _showNewConversationDialog,
        tooltip: 'Trò chuyện mới',
        child: const Icon(Icons.add_comment),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<Conversation>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              final msg = snapshot.error is ApiException
                  ? (snapshot.error as ApiException).message
                  : 'Không tải được danh sách trò chuyện';
              return _Centered(child: Text(msg));
            }
            final items = snapshot.data ?? const [];
            if (items.isEmpty) {
              return const _Centered(child: Text('Chưa có cuộc trò chuyện nào'));
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _ConversationTile(
                conversation: items[i],
                onTap: () => _openConversation(items[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;

  const _ConversationTile({required this.conversation, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final avatar = conversation.otherUser?.avatarUrl;
    final preview = conversation.latestMessage?.body ?? '';
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundImage: avatar != null ? NetworkImage(avatar) : null,
        child: avatar == null ? const Icon(Icons.person) : null,
      ),
      title: Text(
        conversation.otherUser?.name ?? 'Người dùng',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: preview.isEmpty
          ? null
          : Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: conversation.unreadCount > 0
          ? Badge(label: Text('${conversation.unreadCount}'))
          : null,
    );
  }
}

/// Dialog mở cuộc trò chuyện mới bằng ID người nhận.
/// App không có endpoint tìm user nên nhập trực tiếp user_id.
class NewConversationDialog extends StatefulWidget {
  const NewConversationDialog({super.key});

  @override
  State<NewConversationDialog> createState() => _NewConversationDialogState();
}

class _NewConversationDialogState extends State<NewConversationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _userIdCtrl = TextEditingController();
  final _service = ChatService();
  bool _loading = false;

  @override
  void dispose() {
    _userIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final convo = await _service.openConversation(int.parse(_userIdCtrl.text.trim()));
      if (mounted) Navigator.of(context).pop(convo);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Trò chuyện mới'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _userIdCtrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'ID người nhận',
            hintText: 'Ví dụ: 42',
            prefixIcon: Icon(Icons.person_outline),
            border: OutlineInputBorder(),
          ),
          validator: (v) {
            final id = int.tryParse((v ?? '').trim());
            if (id == null || id < 1) return 'Nhập ID người dùng hợp lệ';
            return null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Bắt đầu'),
        ),
      ],
    );
  }
}

class _Centered extends StatelessWidget {
  final Widget child;
  const _Centered({required this.child});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [const SizedBox(height: 140), Center(child: child)],
    );
  }
}
