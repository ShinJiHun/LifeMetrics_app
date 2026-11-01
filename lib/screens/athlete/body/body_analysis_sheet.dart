import 'package:flutter/material.dart';

import '../../../models/body_analysis.dart';
import '../../../utils/format.dart';

const _amber = Color(0xFFFAC775);

// 요약 화면 상단의 한 줄 AI 분석. 탭하면 전체 분석 시트
class BodyAnalysisCard extends StatelessWidget {
  const BodyAnalysisCard({
    super.key,
    required this.analysis,
    required this.date,
    required this.color,
  });

  final BodyAnalysis analysis;
  final DateTime date;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _amber.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showBodyAnalysisSheet(
          context,
          analysis: analysis,
          date: date,
          color: color,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, color: _amber, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  analysis.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _amber,
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: _amber),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showBodyAnalysisSheet(
  BuildContext context, {
  required BodyAnalysis analysis,
  required DateTime date,
  required Color color,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFF211E36),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => _SheetBody(
        analysis: analysis,
        date: date,
        color: color,
        controller: controller,
      ),
    ),
  );
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.analysis,
    required this.date,
    required this.color,
    required this.controller,
  });

  final BodyAnalysis analysis;
  final DateTime date;
  final Color color;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    final muted = Colors.white.withValues(alpha: 0.6);

    // 안드로이드 제스처 바 같은 하단 시스템 영역만큼 더 띄워 마지막 줄이 가리지 않게
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return ListView(
      controller: controller,
      padding: EdgeInsets.fromLTRB(20, 0, 20, 32 + bottomInset),
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome, color: color, size: 20),
            const SizedBox(width: 8),
            const Text(
              'AI 분석',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Text(
              '${formatDate(date)} 측정',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            a.summary,
            style: const TextStyle(
              color: _amber,
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (a.hasEvaluation) ...[
          const _SectionTitle('현재 평가'),
          if (a.muscle != null)
            _Evaluation(
              icon: Icons.fitness_center,
              label: '근육',
              text: a.muscle!,
            ),
          if (a.fat != null)
            _Evaluation(icon: Icons.water_drop, label: '체지방', text: a.fat!),
          if (a.overall != null)
            _Evaluation(icon: Icons.balance, label: '종합', text: a.overall!),
        ],
        if (a.trend != null) ...[
          const _SectionTitle('변화 추이'),
          Text(
            a.trend!,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              height: 1.6,
            ),
          ),
        ],
        if (a.recommendations.isNotEmpty) ...[
          const _SectionTitle('이렇게 해보세요'),
          for (final r in a.recommendations)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.check_circle_outline,
                      color: color,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      r,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.6),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Evaluation extends StatelessWidget {
  const _Evaluation({
    required this.icon,
    required this.label,
    required this.text,
  });

  final IconData icon;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.7)),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
