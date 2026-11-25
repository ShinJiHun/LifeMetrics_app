import 'package:flutter/material.dart';

import '../services/admin_biometric.dart';

// 관리자 로그인. 지문으로 저장해 둔 로그인이 있으면 지문부터, 아니면(또는 취소하면) 비밀번호.
// 비밀번호로 로그인하면 지문을 쓸 수 있는 폰에서는 다음부터 지문으로 되게 저장. 취소하거나 틀리면 false
Future<bool> loginAdminWithDialog(
  BuildContext context,
  Future<bool> Function(String password) login,
) async {
  final messenger = ScaffoldMessenger.of(context);
  if (await AdminBiometric.unlock()) return true;
  if (!context.mounted) return false;
  final password = await showDialog<String>(
    context: context,
    builder: (_) => const _AdminLoginDialog(),
  );
  if (password == null || password.isEmpty) return false;
  if (await login(password)) {
    if (await AdminBiometric.rememberCurrent()) {
      messenger.showSnackBar(
        const SnackBar(content: Text('다음부터는 지문으로 로그인해요')),
      );
    }
    return true;
  }
  messenger.showSnackBar(const SnackBar(content: Text('비밀번호가 올바르지 않아요')));
  return false;
}

// 관리자 비밀번호 입력. 확인하면 입력값을, 취소하면 null 을 돌려줌
class _AdminLoginDialog extends StatefulWidget {
  const _AdminLoginDialog();

  @override
  State<_AdminLoginDialog> createState() => _AdminLoginDialogState();
}

class _AdminLoginDialogState extends State<_AdminLoginDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('관리자 로그인'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: true,
        decoration: const InputDecoration(labelText: '비밀번호'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        TextButton(onPressed: _submit, child: const Text('로그인')),
      ],
    );
  }
}
