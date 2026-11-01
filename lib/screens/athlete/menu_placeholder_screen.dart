import 'package:flutter/material.dart';

import '../../models/athlete_section.dart';

// 각 메뉴의 실제 화면이 들어갈 자리 (임시 화면)
class MenuPlaceholderScreen extends StatelessWidget {
  const MenuPlaceholderScreen({
    super.key,
    required this.menu,
    required this.color,
  });

  final SectionMenu menu;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(menu.title),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(menu.icon, size: 72, color: color),
            const SizedBox(height: 16),
            Text(
              menu.description,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 8),
            Text(
              '준비 중이에요',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
            ),
          ],
        ),
      ),
    );
  }
}
