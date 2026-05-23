import 'post.dart';

class PostComment {
  final int id;
  final int postId;
  final String content;
  final String? createdAt;
  final PostAuthor? author;

  PostComment({
    required this.id,
    required this.postId,
    required this.content,
    this.createdAt,
    this.author,
  });

  factory PostComment.fromJson(Map<String, dynamic> json) => PostComment(
        id: json['id'] as int,
        postId: (json['post_id'] as num).toInt(),
        content: json['content']?.toString() ?? '',
        createdAt: json['created_at']?.toString(),
        author: json['user'] is Map<String, dynamic>
            ? PostAuthor.fromJson(json['user'] as Map<String, dynamic>)
            : null,
      );
}
