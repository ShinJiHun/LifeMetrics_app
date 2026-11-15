import 'package:flutter/material.dart';

// 화면 하단 버튼 자리. 시스템 내비게이션 바(제스처 바) 높이 위로 여백을 더 줘서
// 버튼이 화면 맨 아래에 붙어 보이지 않게 함. (SafeArea.minimum 은 '최소값'이라
// 내비게이션 바가 더 크면 여백이 더해지지 않음)
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({super.key, required this.child});

  static const extraBottom = 24.0;

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      16,
      8,
      16,
      MediaQuery.viewPaddingOf(context).bottom + extraBottom,
    ),
    child: child,
  );
}
