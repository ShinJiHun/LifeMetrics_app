import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/athlete_section.dart';
import '../../../models/body_record.dart';
import '../../../models/health_snapshot.dart';
import '../../../models/ride.dart';
import '../../../models/workout.dart';
import '../../../services/api_client.dart';
import '../../../services/body_api.dart';
import '../../../services/cut_planner.dart';
import '../../../services/fitness_api.dart';
import '../../../services/health_service.dart';
import '../../../services/ride_api.dart';
import '../../../services/workout_recommender.dart';
import '../../../utils/format.dart';
import 'cut_plan_view.dart';
import 'workout_input_screen.dart';

// 오늘 운동 추천: 부위 · 목표 고르기 → GIF 와 함께 운동 · 무게 · 횟수 → 그대로 입력 화면으로
class WorkoutRecommendScreen extends StatefulWidget {
  const WorkoutRecommendScreen({
    super.key,
    this.api,
    this.bodyApi,
    this.rideApi,
    this.health,
    this.now,
  });

  final FitnessApi? api;
  final BodyApi? bodyApi; // 감량: 인바디 · 목표 · 기초대사량
  final RideApi? rideApi; // 감량: 오늘 따릉이
  final HealthService? health; // 감량: 오늘 걸음 · 활동 칼로리 · 식사
  final DateTime? now; // 테스트에서 '오늘' 고정용

  @override
  State<WorkoutRecommendScreen> createState() => _WorkoutRecommendScreenState();
}

class _WorkoutRecommendScreenState extends State<WorkoutRecommendScreen> {
  static final _color = AthleteSection.fitness.color;

  late final FitnessApi _api = widget.api ?? FitnessApi();
  late final BodyApi _bodyApi = widget.bodyApi ?? BodyApi();
  late final RideApi _rideApi = widget.rideApi ?? RideApi();
  late final HealthService _health = widget.health ?? HealthService();

  static const _lossKey = 'cut_monthly_loss_kg';

  // 감량 모드
  CutBasis? _basis;
  String? _basisError;
  double? _monthlyLoss;
  CutPlan? _cutPlan;
  EnergyInputs? _cutInputs;
  bool _planning = false;

  DateTime get _now => widget.now ?? DateTime.now();

  final _parts = <BodyPart>{};
  TrainingGoal _goal = TrainingGoal.hypertrophy;

  List<ExerciseItem>? _items;
  Map<int, ExerciseRecord> _records = const {};
  bool _historyFailed = false;
  String? _error;

  List<Recommendation>? _recs; // 추천 받기 전엔 null
  List<BodyPart> _recParts = const [];
  int _shuffle = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // 종목과 최근 3달 기록을 함께 받음. 기록은 실패해도 추천은 가능
  Future<void> _load() async {
    final now = widget.now ?? DateTime.now();
    try {
      final itemsF = _api.fetchItems();
      final historyF =
          Future.wait([
            for (var m = 0; m < 3; m++)
              _api.fetchHistory(DateTime(now.year, now.month - m)),
          ]).then<List<WorkoutSession>?>(
            (months) => months.expand((s) => s).toList(),
            onError: (_) => null,
          );
      final items = await itemsF;
      final history = await historyF;
      if (!mounted) return;
      setState(() {
        _items = items;
        _records = WorkoutRecommender.summarize(history ?? const []);
        _historyFailed = history == null;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  bool get _isCut => _goal == TrainingGoal.cut;

  void _setGoal(TrainingGoal g) {
    setState(() => _goal = g);
    if (g == TrainingGoal.cut) _loadBasis();
  }

  // 인바디 · 목표 · 기초대사량. 감량 목표는 저장해 둔 값, 없으면 인바디 목표 기준 권장값
  Future<void> _loadBasis() async {
    if (_basis != null) return;
    setState(() => _basisError = null);
    try {
      final basis = await _bodyApi.fetchCutBasis();
      if (basis.weight == null) {
        throw const ApiException('인바디 기록이 없어 감량 계산을 할 수 없어요');
      }
      double? saved;
      try {
        saved = (await SharedPreferences.getInstance()).getDouble(_lossKey);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _basis = basis;
        _monthlyLoss = (saved ?? _suggestedLoss(basis)).clamp(
          0.5,
          CutPlanner.maxMonthlyLoss(basis.weight!),
        );
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _basisError = e.message);
    }
  }

  double _suggestedLoss(CutBasis b) => CutPlanner.suggestMonthlyLoss(
    weightKg: b.weight!,
    targetWeight: b.targetWeight,
    targetDate: b.targetDate,
    today: _now,
  );

  void _setMonthlyLoss(double v) {
    setState(() {
      _monthlyLoss = v;
      _cutPlan = null; // 목표가 바뀌면 다시 계산하게
    });
    SharedPreferences.getInstance()
        .then((p) => p.setDouble(_lossKey, v))
        .ignore();
  }

  Future<void> _recommend({bool another = false}) async {
    final items = _items;
    if (items == null || (_parts.isEmpty && !_isCut)) return;
    // 고른 순서가 아니라 부위 순서(가슴 → 등 → ... → 유산소)로.
    // 감량이면 유산소는 칼로리 계산으로 따로 처방하므로 웨이트만
    final parts = BodyPart.values
        .where(_parts.contains)
        .where((p) => !_isCut || p != BodyPart.cardio)
        .toList();
    setState(() {
      _shuffle = another ? _shuffle + 1 : 0;
      _recParts = parts;
      _recs = WorkoutRecommender.recommend(
        parts: parts,
        goal: _goal,
        items: items,
        records: _records,
        shuffle: _shuffle,
      );
    });
    if (_isCut && !another) await _planCut();
  }

  // 오늘 걸음 · 활동 칼로리 · 식사(삼성헬스) + 따릉이 + 예정 웨이트 → 유산소 처방
  Future<void> _planCut() async {
    final basis = _basis;
    final loss = _monthlyLoss;
    if (basis == null || loss == null) return;
    setState(() => _planning = true);

    final now = _now;
    final today = DateTime(now.year, now.month, now.day);
    bool isToday(DateTime d) =>
        d.year == today.year && d.month == today.month && d.day == today.day;

    final (health, rides) = await (
      _readHealth(),
      _rideApi.fetchRides().then<List<Ride>>(
        (r) => r,
        onError: (_) => <Ride>[],
      ),
    ).wait;
    final bikes = rides
        .where((r) => r.rideType == RideType.ddareungi && isToday(r.startTime))
        .toList();

    // 인바디보다 삼성헬스 체중이 최근이면 그걸 씀
    var weight = basis.weight!;
    if (health?.weight != null &&
        health!.weighedAt != null &&
        (basis.weightDate == null ||
            health.weighedAt!.isAfter(basis.weightDate!))) {
      weight = health.weight!;
    }
    final meals = health?.todayMeals ?? const <Meal>[];
    final weights = (_recs ?? const []).where((r) => !r.isCardio).length;

    final inputs = EnergyInputs(
      weightKg: weight,
      bmr: basis.bmr ?? weight * 22, // 기초대사량이 없으면 체중 × 22 로 대략
      monthlyLossKg: loss,
      intakeKcal: meals.fold<double>(0, (a, m) => a + (m.calories ?? 0)),
      mealCount: meals.length,
      steps: health?.today.steps,
      activeKcal: health?.today.activeKcal,
      bikeKcal: bikes.fold<double>(0, (a, r) => a + (r.calories ?? 0)),
      bikeMinutes:
          bikes.fold<int>(0, (a, r) => a + (r.movingSeconds ?? 0)) ~/ 60,
      bikeRides: bikes.length,
      strengthMinutes: weights * 8, // 종목당 세트 + 휴식 약 8분
      ftp: basis.ftp,
      hour: now.hour,
    );
    if (!mounted) return;
    setState(() {
      _cutInputs = inputs;
      _cutPlan = CutPlanner.plan(inputs);
      _planning = false;
    });
  }

  // 헬스 커넥트가 없거나 권한이 없으면 null (걸음 · 식사 없이 계산)
  Future<HealthSnapshot?> _readHealth() async {
    try {
      if (await _health.status() != HealthStatus.ready) return null;
      return await _health.fetch(dayCount: 1, now: _now);
    } catch (_) {
      return null;
    }
  }

  void _startInput() {
    final plan = [
      for (final r in _recs ?? const <Recommendation>[])
        if (!r.isCardio)
          (
            r.item,
            [
              for (var s = 1; s <= r.sets; s++)
                WorkoutSet(setNumber: s, weight: r.weight, reps: r.targetReps),
            ],
          ),
    ];
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WorkoutInputScreen(initial: plan)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recs = _recs;
    final hasWeights = recs?.any((r) => !r.isCardio) ?? false;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('오늘 운동 추천'),
      ),
      body: switch ((_items, _error)) {
        (null, final String error) => _Retry(
          message: error,
          color: _color,
          onRetry: () {
            setState(() => _error = null);
            _load();
          },
        ),
        (null, _) => const Center(child: CircularProgressIndicator()),
        _ => ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            24 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          children: [
            _Panel(
              children: [
                const _Label('오늘 어디 운동해요?'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in BodyPart.values)
                      FilterChip(
                        label: Text(p.label),
                        selected: _parts.contains(p),
                        selectedColor: _color.withValues(alpha: 0.3),
                        checkmarkColor: Colors.white,
                        onSelected: (on) => setState(
                          () => on ? _parts.add(p) : _parts.remove(p),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                const _Label('목표'),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<TrainingGoal>(
                    segments: [
                      for (final g in TrainingGoal.values)
                        ButtonSegment(value: g, label: Text(g.label)),
                    ],
                    selected: {_goal},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => _setGoal(s.first),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_goal.sets}세트 · ${_goal.repsMin}~${_goal.repsMax}회 · '
                  '휴식 ${_goal.restSec}초',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
                if (_isCut) ...[
                  const SizedBox(height: 14),
                  switch ((_basis, _monthlyLoss, _basisError)) {
                    (final CutBasis b, final double loss, _) => CutGoalPanel(
                      basis: b,
                      monthlyLoss: loss,
                      suggested: _suggestedLoss(b),
                      color: _color,
                      onChanged: _setMonthlyLoss,
                    ),
                    (_, _, final String error) => Row(
                      children: [
                        Expanded(child: Text(error)),
                        TextButton(
                          onPressed: _loadBasis,
                          child: const Text('다시 시도'),
                        ),
                      ],
                    ),
                    _ => const Center(child: CircularProgressIndicator()),
                  },
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        _planning || (_isCut ? _basis == null : _parts.isEmpty)
                        ? null
                        : _recommend,
                    style: FilledButton.styleFrom(
                      backgroundColor: _color,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(
                      _isCut
                          ? (_parts.isEmpty ? '유산소만 추천 받기' : '추천 받기')
                          : _parts.isEmpty
                          ? '부위를 골라 주세요'
                          : '추천 받기',
                    ),
                  ),
                ),
              ],
            ),
            if (_historyFailed)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  '운동 기록을 불러오지 못해 처음 기준으로 추천해요',
                  style: TextStyle(color: Colors.amber.shade200, fontSize: 12),
                ),
              ),
            if (_isCut && _planning)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_isCut && !_planning && _cutPlan != null) ...[
              const SizedBox(height: 18),
              EnergyCard(plan: _cutPlan!, inputs: _cutInputs!, color: _color),
              const SizedBox(height: 18),
              const Text(
                '헬스장 유산소',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              Text(
                '하나만 골라서 하면 돼요',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
              for (final o in _cutPlan!.options)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: CardioCard(option: o, color: _color),
                ),
            ],
            if (recs != null && (!_isCut || _recParts.isNotEmpty)) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_recParts.map((p) => p.label).join(' · ')} '
                      '추천 ${recs.length}개',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (recs.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => _recommend(another: true),
                      style: TextButton.styleFrom(foregroundColor: _color),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('다른 운동으로'),
                    ),
                ],
              ),
              if (recs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: Text('GIF 가 있는 운동이 아직 없어요')),
                ),
              for (final (i, r) in recs.indexed)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _RecCard(
                    index: i + 1,
                    rec: r,
                    color: _color,
                    onTap: () => _showDetail(r),
                  ),
                ),
            ],
          ],
        ),
      },
      bottomNavigationBar: hasWeights
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                onPressed: _startInput,
                style: FilledButton.styleFrom(
                  backgroundColor: _color,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: const Icon(Icons.edit_note),
                label: const Text(
                  '이대로 운동 입력하기',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            )
          : null,
    );
  }

  void _showDetail(Recommendation r) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF211E36),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            24 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 1,
                child: ExerciseGif(url: r.item.gifUrl),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              r.item.nameKo,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            if (r.item.nameEn != null)
              Text(
                r.item.nameEn!,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              ),
            const SizedBox(height: 12),
            Text(
              planText(r),
              style: TextStyle(
                color: _color,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (r.restSec != null)
              Text(
                '세트 사이 휴식 ${r.restSec}초',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              ),
            const SizedBox(height: 6),
            Text(
              r.reason,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
            if (r.item.description != null) ...[
              const SizedBox(height: 16),
              Text(r.item.description!, style: const TextStyle(height: 1.5)),
            ],
          ],
        ),
      ),
    );
  }
}

// '40kg × 10회 × 4세트', '맨몸 12~20회 × 3세트', '20분'
String planText(Recommendation r) {
  if (r.isCardio) return '${r.minutes}분';
  final reps = r.weight == null
      ? '${r.repsMin}~${r.repsMax}회'
      : '${r.targetReps}회';
  final load = r.weight != null
      ? '${formatNum(r.weight!)}kg × '
      : r.item.equipmentType == 'BODYWEIGHT'
      ? '맨몸 '
      : '';
  return '$load$reps × ${r.sets}세트';
}

// 서버 GIF. 불러오는 중엔 스피너, 실패하면 아이콘
class ExerciseGif extends StatelessWidget {
  const ExerciseGif({super.key, required this.url, this.cacheWidth});

  final String? url;
  final int? cacheWidth; // 목록 썸네일은 작게 디코드해 메모리 절약

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: Colors.white.withValues(alpha: 0.06),
      child: Center(
        child: Icon(
          Icons.fitness_center,
          color: Colors.white.withValues(alpha: 0.3),
        ),
      ),
    );
    if (url == null) return placeholder;
    // 첫 프레임이 실제로 그려지기 전까지는 스피너. loadingBuilder 는 첫 데이터가
    // 오기 전엔 빈 이미지를 넘겨서, 흰 배경 위에 아무것도 안 보이는 상태가 생김
    return Image.network(
      apiUrl(url!),
      fit: BoxFit.contain,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, syncLoaded) => frame == null
          ? ColoredBox(
              color: Colors.white.withValues(alpha: 0.06),
              child: const Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          // GIF 들이 흰 배경이라 맞춰 둠
          : ColoredBox(color: Colors.white, child: child),
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}

class _RecCard extends StatelessWidget {
  const _RecCard({
    required this.index,
    required this.rec,
    required this.color,
    required this.onTap,
  });

  final int index;
  final Recommendation rec;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.55);
    final item = rec.item;

    return Material(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox.square(
                  dimension: 104,
                  child: ExerciseGif(url: item.gifUrl, cacheWidth: 312),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$index. ${item.nameKo}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      [
                        rec.part.label,
                        item.equipmentLabel,
                      ].nonNulls.join(' · '),
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      planText(rec),
                      style: TextStyle(
                        color: color,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rec.reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    ),
  );
}

class _Retry extends StatelessWidget {
  const _Retry({
    required this.message,
    required this.color,
    required this.onRetry,
  });

  final String message;
  final Color color;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.cloud_off, size: 48, color: color),
        const SizedBox(height: 12),
        Text(message),
        TextButton(onPressed: onRetry, child: const Text('다시 시도')),
      ],
    ),
  );
}
