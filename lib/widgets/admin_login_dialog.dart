import 'package:flutter/material.dart';

// 비밀번호를 물어 관리자 로그인. 취소하거나 틀리면 false
Future<bool> loginAdminWithDialog(
  BuildContext context,
  Future<bool> Function(String password) login,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final password = await showDialog<String>(
    context: context,
    builder: (_) => const _AdminLoginDialog(),
  );
  if (password == null || password.isEmpty) return false;
  if (await login(password)) return true;
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
