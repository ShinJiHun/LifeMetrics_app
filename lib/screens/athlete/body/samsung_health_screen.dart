import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../models/athlete_section.dart';
import '../../../models/health_snapshot.dart';
import '../../../services/health_service.dart';
import '../../../utils/format.dart';

// 삼성헬스: 헬스 커넥트에 동기화된 오늘 수치 + 어제 식사 + 최근 7일 걸음 · 수면
class SamsungHealthScreen extends StatefulWidget {
  const SamsungHealthScreen({super.key, this.service});

  final HealthService? service;

  @override
  State<SamsungHealthScreen> createState() => _SamsungHealthScreenState();
}

class _SamsungHealthScreenState extends State<SamsungHealthScreen>
    with WidgetsBindingObserver {
  static final _color = AthleteSection.body.color;

  late final HealthService _service = widget.service ?? HealthService();

  HealthStatus? _status; // 확인 중엔 null
  HealthSnapshot? _snapshot;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 헬스 커넥트 설치 · 권한 화면에서 돌아오면 상태를 다시 확인
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _status != HealthStatus.ready &&
        _status != HealthStatus.unsupported) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final status = await _service.status();
      final snapshot = status == HealthStatus.ready
          ? await _service.fetch()
          : null;
      if (!mounted) return;
      setState(() {
        _status = status;
        _snapshot = snapshot;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '헬스 커넥트를 읽지 못했어요');
    }
  }

  Future<void> _connect() async {
    if (_status == HealthStatus.notInstalled) {
      await _service.install();
      return; // 설치 후 돌아오면 didChangeAppLifecycleState 에서 다시 확인
    }
    await _service.requestAuthorization();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('삼성헬스'),
      ),
      body: switch ((_status, _snapshot, _error)) {
        (_, _, final String error) => _Message(
          icon: Icons.error_outline,
          title: error,
          action: '다시 시도',
          color: _color,
          onPressed: () {
            setState(() => _error = null);
            _load();
          },
        ),
        (null, _, _) => const Center(child: CircularProgressIndicator()),
        (HealthStatus.unsupported, _, _) => _Message(
          icon: Icons.phone_android,
          title: '안드로이드 폰에서만 볼 수 있어요',
          body: '삼성헬스 데이터는 헬스 커넥트를 통해 폰에서 읽어와요',
          color: _color,
        ),
        (HealthStatus.notInstalled, _, _) => _Message(
          icon: Icons.download,
          title: '헬스 커넥트가 필요해요',
          body: '설치하거나 최신 버전으로 업데이트해 주세요',
          action: '헬스 커넥트 설치',
          color: _color,
          onPressed: _connect,
        ),
        (HealthStatus.notAuthorized, _, _) => _Message(
          icon: Icons.link,
          title: '삼성헬스 데이터를 연결해요',
          body:
              '삼성헬스 > 설정 > 헬스 커넥트에서 동기화를 켠 뒤\n'
              '아래 버튼으로 읽기 권한을 허용해 주세요',
          action: '권한 허용',
          color: _color,
          onPressed: _connect,
        ),
        (HealthStatus.ready, final HealthSnapshot s, _) => RefreshIndicator(
          onRefresh: _load,
          child: _buildBody(s),
        ),
        (HealthStatus.ready, null, _) => const Center(
          child: CircularProgressIndicator(),
        ),
      },
    );
  }

  Widget _buildBody(HealthSnapshot s) {
    final today = s.today;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        if (s.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              '아직 받은 데이터가 없어요. 삼성헬스의 헬스 커넥트 동기화가 '
              '켜져 있는지 확인해 주세요',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
        _Label('오늘'),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.9,
          children: [
            _Tile(
              icon: Icons.directions_walk,
              label: '걸음',
              value: today.steps == null ? null : formatThousands(today.steps!),
              unit: '걸음',
              color: _color,
            ),
            _Tile(
              icon: Icons.local_fire_department,
              label: '활동 칼로리',
              value: today.activeKcal == null
                  ? null
                  : formatThousands(today.activeKcal!),
              unit: 'kcal',
              color: _color,
            ),
            _Tile(
              icon: Icons.bedtime,
              label: '지난 밤 수면',
              value: today.sleepMinutes == null
                  ? null
                  : formatDuration(today.sleepMinutes! * 60),
              color: _color,
            ),
            _Tile(
              icon: Icons.favorite,
              label: today.restingHr != null ? '안정시 심박' : '평균 심박',
              value: (today.restingHr ?? today.avgHr)?.toString(),
              unit: 'bpm',
              color: _color,
            ),
          ],
        ),
        if (s.weight != null) ...[
          const SizedBox(height: 20),
          _Label('최근 체성분 · ${formatDate(s.weighedAt!)}'),
          Row(
            children: [
              Expanded(
                child: _Tile(
                  icon: Icons.monitor_weight,
                  label: '체중',
                  value: formatNum(s.weight!),
                  unit: 'kg',
                  color: _color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Tile(
                  icon: Icons.water_drop,
                  label: '체지방률',
                  value: s.bodyFat == null ? null : formatNum(s.bodyFat!),
                  unit: '%',
                  color: _color,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        _Label('어제 식사'),
        _MealsCard(
          meals: s.yesterdayMeals,
          authorized: s.mealsAuthorized,
          color: _color,
          onAuthorize: _connect,
        ),
        const SizedBox(height: 20),
        _Label('최근 7일 걸음'),
        _WeekBars(
          days: s.days,
          valueOf: (d) => d.steps?.toDouble(),
          format: (v) => formatThousands(v),
          color: _color,
        ),
        const SizedBox(height: 20),
        _Label('최근 7일 수면'),
        _WeekBars(
          days: s.days,
          valueOf: (d) => d.sleepMinutes == null ? null : d.sleepMinutes! / 60,
          format: (v) => formatDuration((v * 3600).round()),
          color: const Color(0xFF7C6CF2),
        ),
        if (s.sources.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            '출처: ${s.sources.join(', ')}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
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

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.unit,
  });

  final IconData icon;
  final String label;
  final String? value; // null 이면 기록 없음
  final String? unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value ?? '–',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (value != null && unit != null)
                  TextSpan(
                    text: ' $unit',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// 어제 먹은 음식을 끼니별로 묶고 총 칼로리 · 탄단지 합계
class _MealsCard extends StatelessWidget {
  const _MealsCard({
    required this.meals,
    required this.authorized,
    required this.color,
    required this.onAuthorize,
  });

  final List<Meal> meals;
  final bool authorized;
  final Color color;
  final VoidCallback onAuthorize;

  static double? _total(Iterable<Meal> ms, double? Function(Meal) f) {
    final vs = ms.map(f).whereType<double>();
    return vs.isEmpty ? null : vs.reduce((a, b) => a + b);
  }

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.55);
    final Widget child;
    if (!authorized) {
      child = Row(
        children: [
          Expanded(
            child: Text('식사 기록 권한이 필요해요', style: TextStyle(color: muted)),
          ),
          FilledButton(
            onPressed: onAuthorize,
            style: FilledButton.styleFrom(backgroundColor: color),
            child: const Text('권한 허용'),
          ),
        ],
      );
    } else if (meals.isEmpty) {
      child = Text('어제 기록된 식사가 없어요', style: TextStyle(color: muted));
    } else {
      final kcal = _total(meals, (m) => m.calories);
      final macros = [
        ('탄수화물', _total(meals, (m) => m.carbs)),
        ('단백질', _total(meals, (m) => m.protein)),
        ('지방', _total(meals, (m) => m.fat)),
      ].where((e) => e.$2 != null);

      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: kcal == null ? '–' : formatThousands(kcal),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (kcal != null)
                  TextSpan(
                    text: ' kcal',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
              ],
            ),
          ),
          if (macros.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              macros.map((e) => '${e.$1} ${formatNum(e.$2!)}g').join(' · '),
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
          for (final kind in MealKind.values)
            if (meals.where((m) => m.type == kind).toList() case final ms
                when ms.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    kind.label,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (_total(ms, (m) => m.calories) case final k?)
                    Text(
                      '${formatThousands(k)} kcal',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                ],
              ),
              for (final m in ms)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          m.name?.isNotEmpty == true ? m.name! : '이름 없는 음식',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (m.calories != null)
                        Text(
                          formatThousands(m.calories!),
                          style: TextStyle(color: muted, fontSize: 13),
                        ),
                    ],
                  ),
                ),
            ],
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

// 요일별 막대. 터치하면 값 툴팁
class _WeekBars extends StatelessWidget {
  const _WeekBars({
    required this.days,
    required this.valueOf,
    required this.format,
    required this.color,
  });

  final List<DailyHealth> days;
  final double? Function(DailyHealth) valueOf;
  final String Function(double) format;
  final Color color;

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  Widget build(BuildContext context) {
    final values = days.map((d) => valueOf(d) ?? 0).toList();
    final maxY = values.fold<double>(0, (a, b) => a > b ? a : b);

    return Container(
      height: 160,
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: BarChart(
        BarChartData(
          maxY: maxY == 0 ? 1 : maxY * 1.15,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (x, _) => Text(
                  x.toInt() == days.length - 1
                      ? '오늘'
                      : _weekdays[days[x.toInt()].day.weekday - 1],
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF211E36),
              getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                '${formatShortDate(days[group.x].day)}\n${format(rod.toY)}',
                const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
          barGroups: [
            for (final (i, v) in values.indexed)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: v,
                    width: 18,
                    color: i == days.length - 1
                        ? color
                        : color.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.color,
    this.body,
    this.action,
    this.onPressed,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String? action;
  final Color color;
  final VoidCallback? onPressed;

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
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onPressed,
                style: FilledButton.styleFrom(backgroundColor: color),
                child: Text(action!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
