import 'package:flutter/material.dart';

import '../models/post.dart';
import '../models/post_comment.dart';
import '../services/api_client.dart';
import '../services/post_service.dart';
import '../services/reverb_service.dart';
import '../widgets/post_image_view.dart';

class PostDetailScreen extends StatefulWidget {
  final int postId;
  final Post? initialPost; // render ngay nếu đã có từ feed

  const PostDetailScreen({super.key, required this.postId, this.initialPost});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _service = PostService();
  final _reverb = ReverbService();
  final _commentCtrl = TextEditingController();

  Post? _post;
  final List<PostComment> _comments = [];
  bool _loading = true;
  bool _sending = false;
  bool _realtimeConnected = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _post = widget.initialPost;
    _load();
  }

  @override
  void dispose() {
    _reverb.disconnect();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _service.show(widget.postId),
        _service.comments(widget.postId),
      ]);
      if (!mounted) return;
      final post = results[0] as Post;
      setState(() {
        _post = post;
        _comments
          ..clear()
          ..addAll(results[1] as List<PostComment>);
        _loading = false;
      });
      _connectRealtime(post);
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
          _error = 'Không tải được bài viết';
        });
      }
    }
  }

  /// Kết nối Reverb để nhận bình luận mới realtime. Chỉ kết nối một lần
  /// (pull-to-refresh gọi lại _load nhưng không tạo client mới).
  void _connectRealtime(Post post) {
    if (_realtimeConnected) return;
    final reverb = post.reverb;
    if (reverb == null || reverb.key.isEmpty) return;
    _realtimeConnected = true;
    _reverb.subscribePost(
      settings: reverb,
      postId: widget.postId,
      onComment: _onRealtimeComment,
    );
  }

  void _onRealtimeComment(PostComment comment) {
    if (!mounted) return;
    _addComment(comment);
  }

  /// Chèn comment vào đầu danh sách, bỏ qua nếu đã có (HTTP response của chính
  /// mình và event realtime có thể trùng id).
  bool _addComment(PostComment comment) {
    if (_comments.any((c) => c.id == comment.id)) return false;
    setState(() => _comments.insert(0, comment));
    return true;
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final comment = await _service.addComment(widget.postId, text);
      _commentCtrl.clear();
      if (mounted) {
        FocusScope.of(context).unfocus();
        _addComment(comment);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bài viết')),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          const Divider(height: 1),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _post == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _post == null) {
      return Center(child: Text(_error!));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          if (_post != null) _PostContent(post: _post!),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Bình luận (${_comments.length})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_comments.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Chưa có bình luận nào')),
            )
          else
            ..._comments.map((c) => _CommentTile(comment: c)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _commentCtrl,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendComment(),
                decoration: const InputDecoration(
                  hintText: 'Viết bình luận...',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              onPressed: _sending ? null : _sendComment,
              icon: _sending
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostContent extends StatelessWidget {
  final Post post;
  const _PostContent({required this.post});

  @override
  Widget build(BuildContext context) {
    final avatar = post.author?.avatarUrl;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                child: avatar == null ? const Icon(Icons.person) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.author?.name ?? 'Người dùng',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (post.createdAt != null)
                      Text(
                        post.createdAt!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              Icon(
                post.visibility == 'private' ? Icons.lock : Icons.public,
                size: 16,
                color: Colors.grey,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(post.content),
          if (post.images.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final img in post.images)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: PostImageView(url: img.imageUrl),
                ),
              ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                post.isLiked ? Icons.favorite : Icons.favorite_border,
                size: 18,
                color: post.isLiked ? Colors.red : Colors.grey,
              ),
              const SizedBox(width: 4),
              Text('${post.likesCount}'),
              const SizedBox(width: 16),
              const Icon(Icons.mode_comment_outlined, size: 18, color: Colors.grey),
              const SizedBox(width: 4),
              Text('${post.commentsCount}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final PostComment comment;
  const _CommentTile({required this.comment});

  @override
  Widget build(BuildContext context) {
    final avatar = comment.author?.avatarUrl;
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: avatar != null ? NetworkImage(avatar) : null,
        child: avatar == null ? const Icon(Icons.person, size: 20) : null,
      ),
      title: Text(
        comment.author?.name ?? 'Người dùng',
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(comment.content),
    );
  }
}
