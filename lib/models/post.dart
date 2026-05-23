import 'chat.dart' show ReverbSettings;

class PostAuthor {
  final int id;
  final String? name;
  final String? avatarUrl;

  PostAuthor({required this.id, this.name, this.avatarUrl});

  factory PostAuthor.fromJson(Map<String, dynamic> json) => PostAuthor(
        id: json['id'] as int,
        name: json['name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
      );
}

class PostImage {
  final int id;
  final String? imageUrl;
  final int? sortOrder;

  PostImage({required this.id, this.imageUrl, this.sortOrder});

  factory PostImage.fromJson(Map<String, dynamic> json) => PostImage(
        id: json['id'] as int,
        imageUrl: json['image_url'] as String?,
        sortOrder: json['sort_order'] as int?,
      );
}

class Post {
  final int id;
  final String content;
  final String visibility;
  final String? status;
  final String? createdAt;
  final int likesCount;
  final int commentsCount;
  final bool isLiked;
  final PostAuthor? author;
  final List<PostImage> images;
  final ReverbSettings? reverb;

  Post({
    required this.id,
    required this.content,
    required this.visibility,
    this.status,
    this.createdAt,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.isLiked = false,
    this.author,
    this.images = const [],
    this.reverb,
  });

  factory Post.fromJson(Map<String, dynamic> json) => Post(
        id: json['id'] as int,
        content: json['content']?.toString() ?? '',
        visibility: json['visibility']?.toString() ?? 'public',
        status: json['status']?.toString(),
        createdAt: json['created_at']?.toString(),
        likesCount: (json['likes_count'] as num?)?.toInt() ?? 0,
        commentsCount: (json['comments_count'] as num?)?.toInt() ?? 0,
        isLiked: json['is_liked'] == true,
        author: json['user'] is Map<String, dynamic>
            ? PostAuthor.fromJson(json['user'] as Map<String, dynamic>)
            : null,
        images: (json['images'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(PostImage.fromJson)
                .toList() ??
            const [],
        reverb: json['reverb'] is Map<String, dynamic>
            ? ReverbSettings.fromJson(json['reverb'] as Map<String, dynamic>)
            : null,
      );
}
