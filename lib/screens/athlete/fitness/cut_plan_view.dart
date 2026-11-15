import 'package:flutter/material.dart';

import '../../../models/body_record.dart';
import '../../../services/cut_planner.dart';
import '../../../utils/format.dart';
import 'workout_recommend_screen.dart' show ExerciseGif;

// 감량 목표: 한 달 몇 kg. 인바디 목표 기준 권장값과 상한을 함께 보여줌
class CutGoalPanel extends StatelessWidget {
  const CutGoalPanel({
    super.key,
    required this.basis,
    required this.monthlyLoss,
    required this.suggested,
    required this.color,
    required this.onChanged,
  });

  final CutBasis basis;
  final double monthlyLoss;
  final double suggested;
  final Color color;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.55);
    final w = basis.weight!;
    final max = CutPlanner.maxMonthlyLoss(w);
    final perDay = monthlyLoss * kcalPerKgFat / 30;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '한 달 감량 목표',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: '0.5kg 줄이기',
              onPressed: monthlyLoss > 0.5
                  ? () => onChanged(monthlyLoss - 0.5)
                  : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text(
              '${formatNum(monthlyLoss)}kg',
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            IconButton(
              tooltip: '0.5kg 늘리기',
              onPressed: monthlyLoss < max
                  ? () => onChanged(monthlyLoss + 0.5)
                  : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        Text(
          [
            '인바디 ${formatNum(w)}kg'
                '${basis.weightDate == null ? '' : ' (${formatShortDate(basis.weightDate!)})'}',
            if (basis.targetWeight != null)
              '목표 ${formatNum(basis.targetWeight!)}kg'
                  '${basis.targetDate == null ? '' : ' · ${formatDate(basis.targetDate!)}'}',
          ].join(' → '),
          style: TextStyle(color: muted, fontSize: 12),
        ),
        Text(
          '권장 ${formatNum(suggested)}kg · 최대 ${formatNum(max)}kg (주 1%) · '
          '하루 약 ${perDay.round()}kcal 적자',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ],
    );
  }
}

// 오늘 먹은 것 · 쓴 것 · 남은 적자
class EnergyCard extends StatelessWidget {
  const EnergyCard({
    super.key,
    required this.plan,
    required this.inputs,
    required this.color,
  });

  final CutPlan plan;
  final EnergyInputs inputs;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.55);
    final balance = plan.balance;

    Widget row(String label, String value, {String? sub, bool bold = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label),
                    if (sub != null)
                      Text(sub, style: TextStyle(color: muted, fontSize: 12)),
                  ],
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        );

    String kcal(double v) => '${formatThousands(v)}kcal';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '오늘 칼로리 분석',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          row(
            '먹은 것',
            plan.intake == null ? '기록 없음' : kcal(plan.intake!),
            sub: plan.intake == null
                ? '삼성헬스에 식사를 기록하면 더 정확해요'
                : '식사 ${inputs.mealCount}건 · 지금까지',
          ),
          const Divider(height: 16),
          row('기초대사', kcal(plan.bmr), sub: '인바디 기준'),
          row(
            '일상 활동',
            kcal(plan.activeKcal),
            sub: [
              if (inputs.steps != null) '${formatThousands(inputs.steps!)}보',
              plan.activeFromSteps ? '걸음으로 추정' : '삼성헬스 활동 칼로리',
            ].join(' · '),
          ),
          if (inputs.bikeRides > 0)
            row(
              '따릉이',
              kcal(plan.bikeKcal),
              sub: '${inputs.bikeRides}회 · ${inputs.bikeMinutes}분',
            ),
          if (plan.strengthKcal > 0)
            row(
              '오늘 웨이트 (예정)',
              kcal(plan.strengthKcal),
              sub: '약 ${inputs.strengthMinutes}분',
            ),
          if (plan.tef > 0) row('소화', kcal(plan.tef), sub: '먹은 것의 10%'),
          row('쓴 것 합계', kcal(plan.burned), bold: true),
          const Divider(height: 16),
          row('목표 적자', kcal(plan.targetDeficit), sub: '하루 기준'),
          if (balance != null)
            row(
              '지금 수지',
              '${balance > 0 ? '+' : ''}${kcal(balance)}',
              sub: balance < 0 ? '적자' : '흑자 (더 먹음)',
            ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              plan.remaining <= 0
                  ? '목표 적자 달성! 유산소는 회복용으로'
                  : '유산소로 약 ${kcal(plan.remaining)} 더 태우기',
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          for (final n in plan.notes)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      n,
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// 유산소 한 가지 (GIF · 시간 · 강도 · 설정)
class CardioCard extends StatelessWidget {
  const CardioCard({super.key, required this.option, required this.color});

  final CardioOption option;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.55);
    final o = option;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: o.primary ? Border.all(color: color, width: 1.5) : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox.square(
              dimension: 96,
              child: ExerciseGif(url: o.gifUrl, cacheWidth: 288),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        o.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (o.primary) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '오늘 추천',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(o.intensity, style: TextStyle(color: muted, fontSize: 12)),
                const SizedBox(height: 6),
                Text(
                  '${o.minutes}분 · 약 ${o.kcal.round()}kcal',
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(o.how, style: TextStyle(color: muted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
