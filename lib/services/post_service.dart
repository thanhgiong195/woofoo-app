import '../config/api_config.dart';
import '../models/post.dart';
import '../models/post_comment.dart';
import 'api_client.dart';

/// Một trang feed: danh sách bài viết kèm thông tin phân trang.
class PostPage {
  final List<Post> items;
  final int currentPage;
  final int lastPage;

  PostPage({
    required this.items,
    required this.currentPage,
    required this.lastPage,
  });

  /// Còn trang tiếp theo để tải thêm hay không.
  bool get hasMore => currentPage < lastPage;
}

class PostService {
  final _api = ApiClient.instance;

  /// Lấy feed bài viết (phân trang). Trả về [PostPage] gồm danh sách + meta
  /// phân trang để màn hình biết đã tới trang cuối hay chưa.
  Future<PostPage> feed({int page = 1, int perPage = 20}) async {
    final data = await _api.request(
      'GET',
      ApiConfig.posts,
      query: {'page': page, 'per_page': perPage},
    );
    final map = data is Map<String, dynamic> ? data : const <String, dynamic>{};
    final list = (map['list'] ?? data) as List?;
    final paginate = map['paginate'] as Map<String, dynamic>?;
    return PostPage(
      items: list
              ?.whereType<Map<String, dynamic>>()
              .map(Post.fromJson)
              .toList() ??
          const [],
      currentPage: (paginate?['current_page'] as num?)?.toInt() ?? page,
      lastPage: (paginate?['last_page'] as num?)?.toInt() ?? page,
    );
  }

  /// Chi tiết 1 bài viết.
  Future<Post> show(int id) async {
    final data = await _api.request('GET', ApiConfig.post(id));
    return Post.fromJson(data as Map<String, dynamic>);
  }

  /// Danh sách bình luận của bài viết (phân trang).
  Future<List<PostComment>> comments(int id, {int page = 1, int perPage = 20}) async {
    final data = await _api.request(
      'GET',
      ApiConfig.postComments(id),
      query: {'page': page, 'per_page': perPage},
    );
    final list = (data is Map<String, dynamic> ? data['list'] : data) as List?;
    return list
            ?.whereType<Map<String, dynamic>>()
            .map(PostComment.fromJson)
            .toList() ??
        const [];
  }

  /// Gửi bình luận mới, trả về comment vừa tạo.
  Future<PostComment> addComment(int id, String content) async {
    final data = await _api.request(
      'POST',
      ApiConfig.postComments(id),
      data: {'content': content},
    );
    return PostComment.fromJson(data as Map<String, dynamic>);
  }
}
