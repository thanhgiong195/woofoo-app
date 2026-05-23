import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/post.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../services/post_service.dart';
import '../widgets/post_image_view.dart';
import 'post_detail_screen.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _service = PostService();
  final _scrollCtrl = ScrollController();

  final List<Post> _posts = [];
  bool _loading = true; // tải trang đầu
  bool _loadingMore = false; // đang tải thêm trang
  String? _error;
  int _currentPage = 0;
  int _lastPage = 1;

  bool get _hasMore => _currentPage < _lastPage;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Gần tới đáy (còn 300px) thì tải thêm.
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _service.feed(page: 1);
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(page.items);
        _currentPage = page.currentPage;
        _lastPage = page.lastPage;
        _loading = false;
      });
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
          _error = 'Không tải được bảng tin';
        });
      }
    }
  }

  Future<void> _loadMore() async {
    // Dừng khi current_page == last_page, hoặc đang tải dở.
    if (_loadingMore || _loading || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _service.feed(page: _currentPage + 1);
      if (!mounted) return;
      setState(() {
        _posts.addAll(page.items);
        _currentPage = page.currentPage;
        _lastPage = page.lastPage;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _reload() => _loadFirstPage();

  void _openDetail(Post post) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder:
                (_) => PostDetailScreen(postId: post.id, initialPost: post),
          ),
        )
        .then((_) => _reload());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bảng tin'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Đăng xuất',
            onPressed: () => context.read<AuthProvider>().logout(),
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _reload, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _posts.isEmpty) {
      return _ErrorView(message: _error!, onRetry: _reload);
    }
    if (_posts.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          Center(child: Text('Chưa có bài viết nào')),
        ],
      );
    }
    return ListView.separated(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(12),
      // +1 cho footer (loading thêm / hết bài).
      itemCount: _posts.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        if (i >= _posts.length) return _buildFooter();
        return _PostCard(post: _posts[i], onTap: () => _openDetail(_posts[i]));
      },
    );
  }

  Widget _buildFooter() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('Đã hết bài viết', style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _PostCard extends StatelessWidget {
  final Post post;
  final VoidCallback? onTap;
  const _PostCard({required this.post, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundImage:
                        post.author?.avatarUrl != null
                            ? NetworkImage(post.author!.avatarUrl!)
                            : null,
                    child:
                        post.author?.avatarUrl == null
                            ? const Icon(Icons.person)
                            : null,
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
              const SizedBox(height: 10),
              Text(post.content),
              if (post.images.isNotEmpty) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: PostImageView(url: post.images.first.imageUrl),
                ),
              ],
              const SizedBox(height: 10),
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
                  const Icon(
                    Icons.mode_comment_outlined,
                    size: 18,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text('${post.commentsCount}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Center(
          child: Column(
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 8),
              Text(message),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
