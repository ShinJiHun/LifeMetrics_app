import 'package:flutter/material.dart';

enum Persona {
  human(
    title: '인간',
    subtitle: '일상 · 수면 · 기분',
    description: '하루의 리듬과 컨디션을 기록해요',
    icon: Icons.self_improvement,
    color: Color(0xFF7C6CF2),
  ),
  athlete(
    title: '애슬리트',
    subtitle: '운동 · 체력 · 회복',
    description: '훈련량과 퍼포먼스를 추적해요',
    icon: Icons.directions_run,
    color: Color(0xFFFF7A45),
  ),
  developer(
    title: '개발자',
    subtitle: '커밋 · 집중 · 학습',
    description: '코딩 습관과 몰입 시간을 측정해요',
    icon: Icons.terminal,
    color: Color(0xFF2EC4B6),
  ),
  investor(
    title: '증권',
    subtitle: '자산 · 수익률 · 매매',
    description: '포트폴리오와 투자 기록을 관리해요',
    icon: Icons.candlestick_chart,
    color: Color(0xFFE94F64),
  );

  const Persona({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final Color color;
}
