import 'package:flutter/material.dart';

import '../models/persona.dart';
import '../services/persona_store.dart';
import '../widgets/category_card.dart';
import 'daily_insight_screen.dart';
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
              // 남은 높이에 맞춰 카드 비율을 정해 4개가 스크롤 없이 보이게 함
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    const gap = 14.0;
                    const minCardHeight = 130.0;
                    final cardW = (box.maxWidth - gap) / 2;
                    final fitH = (box.maxHeight - gap) / 2;
                    final fits = fitH >= minCardHeight;
                    // 공간이 넉넉하면 원래 비율(0.78)보다 길쭉해지지 않게
                    final ratio = fits
                        ? (cardW / fitH).clamp(0.78, double.infinity)
                        : cardW / minCardHeight;
                    return GridView.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: gap,
                      crossAxisSpacing: gap,
                      childAspectRatio: ratio,
                      physics: fits
                          ? const NeverScrollableScrollPhysics()
                          : null,
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
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              const _InsightTile(),
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

// 페르소나 4개를 엮은 하루 종합 분석으로 들어가는 버튼
class _InsightTile extends StatelessWidget {
  const _InsightTile();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const DailyInsightScreen())),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                for (final p in Persona.values) p.color.withValues(alpha: 0.2),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '종합 분석',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '개발 · 일상 · 운동 · 투자로 돌아보는 하루',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}
