import 'package:flutter/material.dart';

import '../../../models/athlete_section.dart';
import '../../../models/today_plan.dart';
import '../../../services/fitness_api.dart';
import 'workout_input_screen.dart';

// 피트니스 > 입력: '오늘 추천 운동 입력' 과 '직접 입력' 중 고르게 함.
// 오늘 저장한 추천이 없으면 추천 쪽은 눌리지 않음
Future<void> openWorkoutInput(
  BuildContext context, {
  FitnessApi? api,
  DateTime? now,
}) async {
  final plan = await TodayPlanStore.load(now ?? DateTime.now());
  if (!context.mounted) return;
  final color = AthleteSection.fitness.color;
  final muted = Colors.white.withValues(alpha: 0.55);

  final usePlan = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    backgroundColor: const Color(0xFF211E36),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '어떻게 입력할까요?',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _Choice(
              icon: Icons.auto_awesome,
              title: '오늘 추천 운동 입력',
              subtitle: plan == null
                  ? '저장한 오늘 추천이 없어요. 오늘 운동 추천에서 저장해 주세요'
                  : [
                      if (plan.logged) '기록 완료',
                      if (plan.exercises.isNotEmpty)
                        '웨이트 ${plan.exercises.length}개',
                      if (plan.cardio != null)
                        '${plan.cardio!.name} ${plan.cardio!.targetMinutes}분',
                    ].join(' · '),
              color: color,
              muted: muted,
              onTap: plan == null ? null : () => Navigator.pop(context, true),
            ),
            const SizedBox(height: 10),
            _Choice(
              icon: Icons.edit_note,
              title: '직접 입력',
              subtitle: '운동을 하나씩 골라 기록해요',
              color: color,
              muted: muted,
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    ),
  );
  if (usePlan == null || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          WorkoutInputScreen(api: api, now: now, plan: usePlan ? plan : null),
    ),
  );
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.muted,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Color muted;
  final VoidCallback? onTap; // null 이면 흐리게

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onTap == null ? 0.45 : 1,
    child: Material(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(icon, color: color),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: TextStyle(color: muted, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    ),
  );
}
