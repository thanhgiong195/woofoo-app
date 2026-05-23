import 'package:flutter/material.dart';

/// Hiển thị ảnh bài viết với placeholder khi đang tải và khi lỗi (vd 403/404),
/// giữ layout ổn định thay vì để ảnh "nhảy".
class PostImageView extends StatelessWidget {
  final String? url;
  final double height;

  const PostImageView({super.key, required this.url, this.height = 200});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return _placeholder(icon: Icons.image_not_supported_outlined);
    }
    return Image.network(
      url!,
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _placeholder(
          child: const CircularProgressIndicator(strokeWidth: 2),
        );
      },
      errorBuilder: (_, __, ___) =>
          _placeholder(icon: Icons.broken_image_outlined),
    );
  }

  Widget _placeholder({IconData? icon, Widget? child}) {
    return Container(
      height: height,
      width: double.infinity,
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: child ?? Icon(icon, size: 40, color: Colors.grey.shade400),
    );
  }
}
