import 'package:flutter/material.dart';

import '../../models/athlete_section.dart';
import '../../models/today_plan.dart';
import '../../widgets/category_card.dart';
import 'athlete_section_screen.dart';
import 'fitness/workout_input_screen.dart';

// 애슬리트 홈: 4개 파트를 2x2 카드로 보여줌.
// 오늘 저장한 운동 계획이 있으면 위에 띄우고, 아직 기록 전이면 앱을 열 때 바로 그 화면으로
class AthleteHomeScreen extends StatefulWidget {
  const AthleteHomeScreen({super.key, this.now});

  final DateTime? now; // 테스트에서 '오늘' 고정용

  // 앱을 켠 뒤 한 번만 자동으로 띄움 (홈으로 돌아올 때마다 다시 뜨지 않게)
  static bool _autoOpened = false;

  @visibleForTesting
  static void resetAutoOpen() => _autoOpened = false;

  @override
  State<AthleteHomeScreen> createState() => _AthleteHomeScreenState();
}

class _AthleteHomeScreenState extends State<AthleteHomeScreen> {
  TodayPlan? _plan;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadPlan(autoOpen: true);
  }

  Future<void> _loadPlan({bool autoOpen = false}) async {
    final plan = await TodayPlanStore.load(_now);
    if (!mounted) return;
    setState(() => _plan = plan);
    if (autoOpen &&
        plan != null &&
        !plan.logged &&
        !AthleteHomeScreen._autoOpened) {
      AthleteHomeScreen._autoOpened = true;
      _openPlan(plan);
    }
  }

  Future<void> _openPlan(TodayPlan plan) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => WorkoutInputScreen(plan: plan)));
    _loadPlan(); // 돌아오면 기록 여부가 바뀌었을 수 있음
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final color = AthleteSection.fitness.color;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '오늘은 무엇을 기록할까요?',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 14,
            ),
          ),
          if (plan != null) ...[
            const SizedBox(height: 14),
            Material(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
              child: ListTile(
                leading: Icon(
                  plan.logged ? Icons.check_circle : Icons.fitness_center,
                  color: color,
                ),
                title: Text(
                  plan.logged ? '오늘 운동 기록 완료' : '오늘의 운동',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  [
                    if (plan.exercises.isNotEmpty)
                      '웨이트 ${plan.exercises.length}개',
                    if (plan.cardio != null)
                      '${plan.cardio!.name} ${plan.cardio!.targetMinutes}분',
                  ].join(' · '),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openPlan(plan),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.78,
              children: [
                for (final section in AthleteSection.values)
                  CategoryCard(
                    icon: section.icon,
                    title: section.title,
                    subtitle: section.subtitle,
                    description: section.description,
                    color: section.color,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              AthleteSectionScreen(section: section),
                        ),
                      );
                      _loadPlan(); // 추천 화면에서 새로 저장했을 수 있음
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
