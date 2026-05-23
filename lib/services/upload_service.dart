import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../config/api_config.dart';
import 'api_client.dart';

/// Kết quả upload: object key trên S3 + mime đã được server ký.
class UploadedFile {
  final String path; // file_path (S3 key) — lưu vào resource, KHÔNG phải URL
  final String mime; // content_type đã resolve (vd image/jpeg)

  UploadedFile({required this.path, required this.mime});
}

/// Upload file lên S3 qua presigned URL (giống useS3Upload.ts bên Vue).
class UploadService {
  final _api = ApiClient.instance;

  /// [contentTypeKey] là một trong các giá trị API chấp nhận:
  /// jpg|jpeg|png cho ảnh; pdf|doc|docx cho tài liệu.
  Future<UploadedFile> upload({
    required Uint8List bytes,
    required String filename,
    required String prefix,
    required String contentTypeKey,
  }) async {
    // 1) Lấy presigned URL.
    final data = await _api.request(
      'POST',
      ApiConfig.presignedUrl,
      data: {
        'filename': filename,
        'prefix': prefix,
        'content_type': contentTypeKey,
      },
    ) as Map<String, dynamic>;

    final uploadUrl = data['upload_url'] as String;
    final filePath = data['file_path'] as String;
    final mime = data['content_type'] as String;

    // 2) PUT bytes lên S3 với đúng Content-Type đã ký.
    // Gửi Uint8List trực tiếp để Dio đặt Content-Length cố định (S3 presigned
    // PUT không chấp nhận Transfer-Encoding: chunked).
    await Dio().put(
      uploadUrl,
      data: bytes,
      options: Options(
        headers: {
          Headers.contentTypeHeader: mime,
          Headers.contentLengthHeader: bytes.length,
        },
      ),
    );

    return UploadedFile(path: filePath, mime: mime);
  }
}
