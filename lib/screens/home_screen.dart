import 'package:flutter/material.dart';

import '../models/persona.dart';
import 'athlete/athlete_home_screen.dart';
import 'human/diary_screen.dart';
import 'investor/stock_screen.dart';
import 'persona_select_screen.dart';

// 페르소나별 대시보드 (애슬리트 · 인간 · 증권 외에는 아직 임시 화면).
// 앱의 첫 화면이라 뒤로가기를 누르면 앱을 닫지 않고 페르소나 선택으로 감 (거기서 한 번 더 누르면 종료)
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.persona});

  final Persona persona;

  void _toPersonaSelect(BuildContext context) =>
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => PersonaSelectScreen(initial: persona)),
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _toPersonaSelect(context);
      },
      child: _scaffold(context),
    );
  }

  Widget _scaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF15122B),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(
          switch (persona) {
            Persona.human => '인간 · 하루 일기',
            Persona.investor => '증권 · 토스 계좌',
            _ => '${persona.title} 대시보드',
          },
        ),
        actions: [
          IconButton(
            tooltip: '페르소나 변경',
            icon: const Icon(Icons.swap_horiz),
            onPressed: () => _toPersonaSelect(context),
          ),
        ],
      ),
      // 안드로이드 15+ 는 화면이 시스템 버튼 아래까지 그려지므로 아래 여백을 둬서 카드가 가리지 않게 함
      body: SafeArea(
        top: false,
        child: switch (persona) {
          Persona.athlete => const AthleteHomeScreen(),
          Persona.human => const DiaryScreen(),
          Persona.investor => const StockScreen(),
          _ => _PlaceholderBody(persona: persona),
        },
      ),
    );
  }
}

class _PlaceholderBody extends StatelessWidget {
  const _PlaceholderBody({required this.persona});

  final Persona persona;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(persona.icon, size: 72, color: persona.color),
          const SizedBox(height: 16),
          Text(
            persona.description,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }
}
