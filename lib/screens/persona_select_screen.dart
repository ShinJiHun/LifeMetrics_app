import 'package:flutter/material.dart';

import '../models/persona.dart';
import '../services/persona_store.dart';
import '../widgets/category_card.dart';
import 'home_screen.dart';

class PersonaSelectScreen extends StatefulWidget {
  const PersonaSelectScreen({super.key, this.initial});

  // 홈에서 페르소나를 바꾸러 들어온 경우 현재 페르소나를 미리 선택
  final Persona? initial;

  @override
  State<PersonaSelectScreen> createState() => _PersonaSelectScreenState();
}

class _PersonaSelectScreenState extends State<PersonaSelectScreen> {
  late Persona? _selected = widget.initial;

  Future<void> _start() async {
    final persona = _selected;
    if (persona == null) return;
    await PersonaStore.save(persona);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomeScreen(persona: persona)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = _selected?.color ?? const Color(0xFF7C6CF2);

    return Scaffold(
      backgroundColor: const Color(0xFF15122B),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '어떤 나를 측정할까요?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '페르소나에 맞춰 대시보드와 지표가 구성돼요',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.78,
                  children: [
                    for (final persona in Persona.values)
                      CategoryCard(
                        icon: persona.icon,
                        title: persona.title,
                        subtitle: persona.subtitle,
                        description: persona.description,
                        color: persona.color,
                        selected: persona == _selected,
                        onTap: () => setState(() => _selected = persona),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: _selected == null ? null : _start,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    disabledBackgroundColor: Colors.white.withValues(
                      alpha: 0.08,
                    ),
                    disabledForegroundColor: Colors.white.withValues(
                      alpha: 0.3,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    _selected == null
                        ? '페르소나를 선택하세요'
                        : '${_selected!.title}로 시작하기',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
