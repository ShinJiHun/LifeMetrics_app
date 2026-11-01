import 'package:flutter/material.dart';

import '../../../models/athlete_section.dart';
import '../../../models/ride.dart';
import '../../../models/ride_detail.dart';
import '../../../services/api_client.dart';
import '../../../services/ride_api.dart';
import '../../../utils/format.dart';
import 'ride_feed_screen.dart';
import 'ride_route_map.dart';

// 라이딩 상세: 경로 지도 → 제목 → 전체 기록 → AI 분석 → 구간 기록.
// 피드에서 받은 Ride 로 지도와 제목을 먼저 그리고, 상세 기록은 받아오는 대로 채움
class RideDetailScreen extends StatefulWidget {
  const RideDetailScreen({super.key, required this.ride, this.api});

  final Ride ride;
  final RideApi? api;

  @override
  State<RideDetailScreen> createState() => _RideDetailScreenState();
}

class _RideDetailScreenState extends State<RideDetailScreen> {
  static final _color = AthleteSection.riding.color;

  late final RideApi _api = widget.api ?? RideApi();

  RideDetail? _detail;
  String? _error;
  // 분석과 구간은 없어도 화면은 보여줌. 받기 전엔 null
  RideAnalysis? _analysis;
  bool _analysisLoaded = false;
  List<RideSegment>? _segments;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.ride.id;
    _api.fetchAnalysis(id).then((a) {
      if (mounted) {
        setState(() {
          _analysis = a;
          _analysisLoaded = true;
        });
      }
    });
    _api.fetchSegments(id).then((s) => s, onError: (_) => <RideSegment>[]).then(
      (s) {
        if (mounted) setState(() => _segments = s);
      },
    );
    try {
      final detail = await _api.fetchDetail(id);
      if (mounted) {
        setState(() {
          _detail = detail;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _retry() {
    setState(() {
      _error = null;
      _detail = null;
      _analysisLoaded = false;
      _segments = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final r = _detail?.ride ?? widget.ride;
    final segments = _segments;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('라이딩'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _RouteHeader(ride: r)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverList.list(
              children: [
                _TitleBlock(ride: r, color: _color),
                const SizedBox(height: 16),
                switch ((_detail, _error)) {
                  (final RideDetail d, _) => _StatsGrid(detail: d),
                  (null, final String error) => _ErrorBox(
                    message: error,
                    color: _color,
                    onRetry: _retry,
                  ),
                  _ => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                },
                if (_analysis case final a?) ...[
                  const SizedBox(height: 24),
                  _AnalysisCard(analysis: a, color: _color),
                ] else if (!_analysisLoaded && _error == null) ...[
                  const SizedBox(height: 24),
                  const _SectionTitle('AI 분석'),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                if (segments != null && segments.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _SectionTitle('구간 ${segments.length}개'),
                ],
              ],
            ),
          ),
          if (segments != null && segments.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList.builder(
                itemCount: segments.length,
                itemBuilder: (_, i) => _SegmentTile(
                  key: ValueKey(segments[i].id),
                  segment: segments[i],
                ),
              ),
            )
          else
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

// 정지 지도, 누르면 전체 화면 지도
class _RouteHeader extends StatelessWidget {
  const _RouteHeader({required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RideRouteMap(route: ride.route, color: RideCard.routeColor),
          if (ride.route.length >= 2)
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RideMapScreen(
                      title: ride.title,
                      route: ride.route,
                      color: RideCard.routeColor,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.ride, required this.color});

  final Ride ride;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final r = ride;
    final muted = Colors.white.withValues(alpha: 0.55);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                formatDateTime(r.startTime),
                style: TextStyle(color: muted, fontSize: 13),
              ),
            ),
            if (r.rideType != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  r.rideType!.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          r.title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        if (r.bikeLabel != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.directions_bike, size: 15, color: muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  r.bikeLabel!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: muted, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// 값이 있는 기록만 2열 격자로
class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.detail});

  final RideDetail detail;

  @override
  Widget build(BuildContext context) {
    final d = detail, r = detail.ride;
    String? fmt(num? v, String Function(num) f) => v == null ? null : f(v);

    final stats = <(String, String?)>[
      (
        '거리',
        fmt(r.distanceMeters, (v) => '${(v / 1000).toStringAsFixed(2)} km'),
      ),
      ('이동 시간', fmt(r.movingSeconds, (v) => formatDuration(v.toInt()))),
      ('획득고도', fmt(r.elevationGain, (v) => '${formatThousands(v)} m')),
      ('경과 시간', fmt(d.elapsedSeconds, (v) => formatDuration(v.toInt()))),
      ('평균 속도', fmt(d.avgSpeed, (v) => '${formatNum(v.toDouble())} km/h')),
      ('최고 속도', fmt(d.maxSpeed, (v) => '${formatNum(v.toDouble())} km/h')),
      ('평균 파워', fmt(r.avgPower, (v) => '${v.round()} W')),
      ('최대 파워', fmt(d.maxPower, (v) => '${v.round()} W')),
      ('평균 심박', fmt(r.avgHeartRate, (v) => '${v.round()} bpm')),
      ('최대 심박', fmt(d.maxHeartRate, (v) => '${v.round()} bpm')),
      ('평균 케이던스', fmt(d.avgCadence, (v) => '${v.round()} rpm')),
      ('칼로리', fmt(r.calories, (v) => '${formatThousands(v)} kcal')),
      ('상대적 노력', fmt(r.relativeEffort, (v) => '$v')),
      ('하강고도', fmt(d.elevationLoss, (v) => '${formatThousands(v)} m')),
      ('기온', fmt(d.temperature, (v) => '${formatNum(v.toDouble())}°C')),
      ('풍속', fmt(d.windSpeed, (v) => '${formatNum(v.toDouble())} m/s')),
    ];
    final shown = [
      for (final (label, value) in stats)
        if (value != null) (label, value),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final (label, value) in shown)
              Container(
                width: w,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
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
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AnalysisCard extends StatelessWidget {
  const _AnalysisCard({required this.analysis, required this.color});

  final RideAnalysis analysis;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    final muted = Colors.white.withValues(alpha: 0.6);
    final chips = [
      if (a.intensity != null) '강도 ${a.intensity}',
      if (a.pacingGrade != null) '페이스 ${a.pacingGrade}',
      if (a.intensityFactor != null)
        'IF ${a.intensityFactor!.toStringAsFixed(2)}',
      if (a.trainingStress != null) 'TSS ${a.trainingStress}',
    ];

    Widget bullets(String title, List<String> items, IconData icon) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        for (final s in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(icon, size: 15, color: color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: color, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'AI 분석',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              if (a.score != null)
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${a.score}',
                        style: TextStyle(
                          color: color,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      TextSpan(
                        text: ' / 100',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (a.summary != null) ...[
            const SizedBox(height: 10),
            Text(
              a.summary!,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in chips)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(c, style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ],
          if (a.highlights.isNotEmpty)
            bullets('잘한 점', a.highlights, Icons.check_circle_outline),
          if (a.suggestions.isNotEmpty)
            bullets('개선할 점', a.suggestions, Icons.lightbulb_outline),
          for (final (title, body) in a.sections) ...[
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              body,
              style: TextStyle(color: muted, fontSize: 13, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class _SegmentTile extends StatelessWidget {
  const _SegmentTile({super.key, required this.segment});

  // PR 1~3위 메달 색
  static const _rankColors = [
    Color(0xFFF5C542),
    Color(0xFFC0C6CF),
    Color(0xFFCD8B52),
  ];

  final RideSegment segment;

  @override
  Widget build(BuildContext context) {
    final s = segment;
    final rank = s.prRank;
    final parts = [
      if (s.distanceMeters != null) '${formatNum(s.distanceMeters! / 1000)} km',
      if (s.avgGrade != null) '${formatNum(s.avgGrade!)}%',
      if (s.avgPower != null) '${s.avgPower!.round()} W',
      if (s.avgHeartRate != null) '${s.avgHeartRate!.round()} bpm',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          if (rank != null && rank >= 1 && rank <= 3) ...[
            CircleAvatar(
              radius: 13,
              backgroundColor: _rankColors[rank - 1],
              child: Text(
                rank == 1 ? 'PR' : '$rank',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (parts.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    parts.join(' · '),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (s.movingSeconds != null) ...[
            const SizedBox(width: 10),
            Text(
              formatClock(s.movingSeconds!),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

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

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({
    required this.message,
    required this.color,
    required this.onRetry,
  });

  final String message;
  final Color color;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.cloud_off, size: 40, color: color),
          const SizedBox(height: 10),
          Text(message, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onRetry,
            style: FilledButton.styleFrom(backgroundColor: color),
            icon: const Icon(Icons.refresh),
            label: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }
}
