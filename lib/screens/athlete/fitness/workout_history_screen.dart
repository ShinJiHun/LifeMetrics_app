import 'package:flutter/material.dart';

import '../../../models/athlete_section.dart';
import '../../../models/workout.dart';
import '../../../services/api_client.dart';
import '../../../services/fitness_api.dart';
import '../../../utils/format.dart';

// 피트니스 기록: 달별로 운동한 날을 카드로, 누르면 운동별 세트까지 펼침
class WorkoutHistoryScreen extends StatefulWidget {
  const WorkoutHistoryScreen({super.key, this.api, this.now});

  final FitnessApi? api;
  final DateTime? now; // 테스트에서 '이번 달' 고정용

  @override
  State<WorkoutHistoryScreen> createState() => _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends State<WorkoutHistoryScreen> {
  static final _color = AthleteSection.fitness.color;

  late final FitnessApi _api = widget.api ?? FitnessApi();
  late final DateTime _thisMonth = _monthOf(widget.now ?? DateTime.now());
  late DateTime _month = _thisMonth;

  List<WorkoutSession>? _sessions; // 최신 날짜부터, 로딩 중엔 null
  String? _error;
  final _expanded = <int>{}; // 펼친 세션 id
  final _analyses = <int, Future<WorkoutAnalysis?>>{}; // 펼칠 때 한 번만 받음

  static DateTime _monthOf(DateTime d) => DateTime(d.year, d.month);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final month = _month;
    try {
      final sessions = await _api.fetchHistory(month);
      // 그사이 다른 달로 넘겼으면 버림
      if (!mounted || month != _month) return;
      setState(() {
        _sessions = sessions;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted && month == _month) setState(() => _error = e.message);
    }
  }

  void _moveMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _sessions = null;
      _error = null;
      _expanded.clear();
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('피트니스 기록'),
      ),
      body: Column(
        children: [
          _MonthBar(
            month: _month,
            onPrev: () => _moveMonth(-1),
            onNext: _month == _thisMonth ? null : () => _moveMonth(1),
          ),
          Expanded(
            child: switch ((_sessions, _error)) {
              (null, final String error) => _Message(
                icon: Icons.cloud_off,
                text: error,
                color: _color,
                onRetry: () {
                  setState(() => _error = null);
                  _load();
                },
              ),
              (null, _) => const Center(child: CircularProgressIndicator()),
              (final List<WorkoutSession> sessions, _) => RefreshIndicator(
                onRefresh: _load,
                child: sessions.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 100),
                          _Message(
                            icon: Icons.fitness_center,
                            text: '이 달엔 운동 기록이 없어요',
                            color: _color,
                          ),
                        ],
                      )
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          16,
                          4,
                          16,
                          32 + MediaQuery.viewPaddingOf(context).bottom,
                        ),
                        children: [
                          _MonthSummary(sessions: sessions, color: _color),
                          for (final s in sessions)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: WorkoutSessionCard(
                                key: ValueKey(s.id),
                                session: s,
                                expanded: _expanded.contains(s.id),
                                analysis: _analyses[s.id],
                                onTap: () => setState(() {
                                  if (!_expanded.remove(s.id)) {
                                    _expanded.add(s.id);
                                    _analyses.putIfAbsent(
                                      s.id,
                                      () => _api.fetchAnalysis(s.id),
                                    );
                                  }
                                }),
                              ),
                            ),
                        ],
                      ),
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _MonthBar extends StatelessWidget {
  const _MonthBar({required this.month, required this.onPrev, this.onNext});

  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback? onNext; // 이번 달이면 null

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: '이전 달',
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              '${month.year}년 ${month.month}월',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: '다음 달',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

// 이 달 합계: 운동한 날 · 총 세트 · 총 볼륨
class _MonthSummary extends StatelessWidget {
  const _MonthSummary({required this.sessions, required this.color});

  final List<WorkoutSession> sessions;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final sets = sessions.fold<int>(0, (sum, s) => sum + (s.totalSets ?? 0));
    final volume = sessions.fold<double>(
      0,
      (sum, s) => sum + (s.totalVolume ?? 0),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _Stat(label: '운동한 날', value: '${sessions.length}일'),
          _Stat(label: '총 세트', value: '$sets'),
          _Stat(label: '총 볼륨', value: '${formatThousands(volume)} kg'),
        ],
      ),
    );
  }
}

// 하루 운동 카드. 접혀 있을 땐 운동 이름만, 펼치면 세트별 무게 × 횟수
class WorkoutSessionCard extends StatelessWidget {
  const WorkoutSessionCard({
    super.key,
    required this.session,
    required this.expanded,
    required this.onTap,
    this.analysis,
  });

  final WorkoutSession session;
  final bool expanded;
  final VoidCallback onTap;
  final Future<WorkoutAnalysis?>? analysis; // 펼쳤을 때만 보여 줌

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  Widget build(BuildContext context) {
    final s = session;
    final color = AthleteSection.fitness.color;
    final muted = Colors.white.withValues(alpha: 0.55);

    return Material(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${s.date.month}/${s.date.day} '
                    '(${_weekdays[s.date.weekday - 1]})',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (s.isPT) ...[
                    const SizedBox(width: 8),
                    _Badge(text: 'PT', color: color),
                  ],
                  const Spacer(),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: muted,
                  ),
                ],
              ),
              if (s.categories.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  s.categories.join(' · '),
                  style: TextStyle(color: color, fontSize: 13),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  _Stat(label: '운동', value: '${s.exercises.length}개'),
                  _Stat(label: '세트', value: '${s.totalSets ?? '-'}'),
                  _Stat(
                    label: '볼륨',
                    value: s.totalVolume == null
                        ? '-'
                        : '${formatThousands(s.totalVolume!)} kg',
                  ),
                  _Stat(
                    label: '시간',
                    value: s.estimatedMinutes == null
                        ? '-'
                        : '${s.estimatedMinutes}분',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (expanded && analysis != null)
                _AnalysisBox(analysis: analysis!, color: color),
              for (final e in s.exercises)
                expanded
                    ? _ExerciseSets(exercise: e)
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${e.nameKo ?? '운동'}  ·  ${e.sets.length}세트',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13,
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

const _amber = Color(0xFFFAC775);

// 세션 AI 분석: 점수 · 요약 → 볼륨/강도 → 잘한 점 · 다음엔. 분석이 없으면 아무것도 안 그림
class _AnalysisBox extends StatelessWidget {
  const _AnalysisBox({required this.analysis, required this.color});

  final Future<WorkoutAnalysis?> analysis;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: analysis,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _amber,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'AI 분석 불러오는 중',
                  style: TextStyle(
                    color: _amber.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }
        final a = snap.data;
        if (a == null) return const SizedBox.shrink();
        final levels = [
          if (a.volumeLevel != null) '볼륨 ${a.volumeLevel}',
          if (a.intensityLevel != null) '강도 ${a.intensityLevel}',
        ];

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, color: _amber, size: 16),
                  const SizedBox(width: 6),
                  const Text(
                    'AI 분석',
                    style: TextStyle(
                      color: _amber,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (a.score != null)
                    Text(
                      '${a.score}점',
                      style: const TextStyle(
                        color: _amber,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                a.summary,
                style: const TextStyle(
                  color: _amber,
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (levels.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  levels.join(' · '),
                  style: TextStyle(
                    color: _amber.withValues(alpha: 0.75),
                    fontSize: 12,
                  ),
                ),
              ],
              for (final (title, items, icon) in [
                ('잘한 점', a.highlights, Icons.check_circle_outline),
                ('다음엔', a.suggestions, Icons.lightbulb_outline),
              ])
                if (items.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  for (final text in items)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(icon, size: 15, color: color),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              text,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 13,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
            ],
          ),
        );
      },
    );
  }
}

class _ExerciseSets extends StatelessWidget {
  const _ExerciseSets({required this.exercise});

  final WorkoutExercise exercise;

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.55);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exercise.nameKo ?? '운동',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final set in exercise.sets)
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${set.setNumber}  ',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                      TextSpan(
                        text:
                            '${set.weight == null ? '-' : formatNum(set.weight!)}kg'
                            ' × ${set.reps ?? '-'}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    required this.color,
    this.onRetry,
  });

  final IconData icon;
  final String text;
  final Color color;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: color),
            const SizedBox(height: 16),
            Text(
              text,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                style: FilledButton.styleFrom(backgroundColor: color),
                icon: const Icon(Icons.refresh),
                label: const Text('다시 시도'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
