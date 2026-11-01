import 'package:flutter/material.dart';

import '../models/persona.dart';
import 'athlete/athlete_home_screen.dart';
import 'persona_select_screen.dart';

// 페르소나별 대시보드 (애슬리트 외에는 아직 임시 화면)
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.persona});

  final Persona persona;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF15122B),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text('${persona.title} 대시보드'),
        actions: [
          IconButton(
            tooltip: '페르소나 변경',
            icon: const Icon(Icons.swap_horiz),
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => PersonaSelectScreen(initial: persona),
              ),
            ),
          ),
        ],
      ),
      body: switch (persona) {
        Persona.athlete => const AthleteHomeScreen(),
        _ => _PlaceholderBody(persona: persona),
      },
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
