import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../services/upload_service.dart';

/// Màn hình chỉnh sửa thông tin tài khoản: đổi tên (bắt buộc), email và avatar.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _uploader = UploadService();

  bool _saving = false;

  // Avatar đang hiển thị: URL hiện tại từ server.
  String? _currentAvatarUrl;
  // Avatar mới do người dùng chọn (chưa upload): bytes để xem trước + thông tin
  // file để upload khi bấm Lưu.
  Uint8List? _pickedBytes;
  String? _pickedFilename;
  String? _pickedContentTypeKey;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    _nameCtrl.text = (user?['name'] as String?) ?? '';
    _emailCtrl.text = (user?['email'] as String?) ?? '';
    _currentAvatarUrl = user?['avatar_url'] as String?;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : null,
      ),
    );
  }

  /// Chọn ảnh từ thiết bị để xem trước. Chưa upload — chỉ giữ bytes + thông tin
  /// file, việc upload sẽ chạy khi bấm Lưu.
  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.firstOrNull;
    if (file == null || file.bytes == null) return;

    final ext = (file.extension ?? '').toLowerCase();
    if (!['jpg', 'jpeg', 'png'].contains(ext)) {
      _toast('Chỉ hỗ trợ ảnh JPG hoặc PNG.', error: true);
      return;
    }

    setState(() {
      _pickedBytes = file.bytes;
      _pickedFilename = file.name;
      _pickedContentTypeKey = ext == 'jpeg' ? 'jpg' : ext;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    setState(() => _saving = true);
    try {
      // Nếu có ảnh mới được chọn thì upload lên S3 trước để lấy file_path.
      String? avatarPath;
      if (_pickedBytes != null) {
        final uploaded = await _uploader.upload(
          bytes: _pickedBytes!,
          filename: _pickedFilename!,
          prefix: 'profile',
          contentTypeKey: _pickedContentTypeKey!,
        );
        avatarPath = uploaded.path;
      }

      final email = _emailCtrl.text.trim();
      await auth.updateProfile(
        name: _nameCtrl.text.trim(),
        email: email.isEmpty ? null : email,
        avatar: avatarPath,
      );
      _toast('Đã cập nhật thông tin tài khoản.');
      // Giữ lại ảnh xem trước cục bộ để hiển thị ngay (URL từ server có thể
      // chưa sẵn sàng hoặc API không trả về avatar_url). Xoá thông tin file đã
      // upload để lần lưu sau không vô tình upload/gửi lại avatar cũ.
      setState(() {
        _pickedFilename = null;
        _pickedContentTypeKey = null;
        _currentAvatarUrl = auth.user?['avatar_url'] as String? ?? _currentAvatarUrl;
      });
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ImageProvider? avatarImage = _pickedBytes != null
        ? MemoryImage(_pickedBytes!)
        : (_currentAvatarUrl != null
              ? CachedNetworkImageProvider(_currentAvatarUrl!)
              : null);

    return Scaffold(
      appBar: AppBar(title: const Text('Thông tin tài khoản')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 48,
                        backgroundImage: avatarImage,
                        child: avatarImage == null
                            ? const Icon(Icons.person, size: 48)
                            : null,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Material(
                          color: Theme.of(context).colorScheme.primary,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _saving ? null : _pickAvatar,
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(
                                Icons.camera_alt,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _nameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Tên',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Vui lòng nhập tên' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) return null; // email không bắt buộc
                    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                    return emailRegex.hasMatch(value)
                        ? null
                        : 'Email không hợp lệ';
                  },
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Lưu thay đổi'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
