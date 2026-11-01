import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../models/athlete_section.dart';
import '../../../models/body_analysis.dart';
import '../../../models/body_record.dart';
import '../../../services/api_client.dart';
import '../../../services/body_api.dart';
import '../../../utils/format.dart';
import '../../../widgets/admin_login_dialog.dart';
import 'body_analysis_sheet.dart';
import 'inbody_trend_chart.dart';

// 인바디 / FitDays: 서버 기록을 측정 종류별로 요약 → 지표별 추이 차트 → 전체 기록 목록
class InbodyScreen extends StatefulWidget {
  const InbodyScreen({super.key, this.api, this.pickImage});

  final BodyApi? api;
  // 기록지 사진 고르기. 테스트에서 갤러리 대신 쓸 함수, 없으면 image_picker
  final Future<XFile?> Function(ImageSource source)? pickImage;

  @override
  State<InbodyScreen> createState() => _InbodyScreenState();
}

class _InbodyScreenState extends State<InbodyScreen> {
  static final _color = AthleteSection.body.color;

  late final BodyApi _api = widget.api ?? BodyApi();

  List<BodyRecord>? _records; // 날짜 오름차순, 로딩 중엔 null
  String? _error;
  MeasurementType _type = MeasurementType.inbody;
  BodyMetric _metric = BodyMetric.weight;
  BodyPeriod _period = BodyPeriod.all;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load(initial: true);
  }

  Future<void> _load({bool initial = false}) async {
    try {
      final records = await _api.fetchRecords();
      if (!mounted) return;
      setState(() {
        _records = records;
        _error = null;
        // 인바디 기록이 없으면 FitDays 부터 보여줌
        if (initial && !records.any((r) => r.type == MeasurementType.inbody)) {
          _type = MeasurementType.fitdays;
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _retry() async {
    setState(() {
      _error = null;
      _records = null;
    });
    await _load(initial: true);
  }

  // 카메라/갤러리에서 기록지 사진을 골라 업로드. 서버가 AI 로 읽는 동안
  // 기록이 바로 생기지 않아 잠시 뒤에 다시 불러옴
  Future<void> _upload() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                '인바디 기록지 업로드',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('카메라로 찍기'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('사진에서 고르기'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    // 기록지 글씨만 읽히면 되므로 줄여서 보냄
    final pick =
        widget.pickImage ??
        (s) => ImagePicker().pickImage(
          source: s,
          maxWidth: 2000,
          maxHeight: 2000,
          imageQuality: 85,
        );
    final file = await pick(source);
    if (file == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _uploading = true);
    try {
      // 이름이 비어 오는 경우(웹 등)엔 확장자 있는 기본 이름으로
      final name = file.name.isEmpty ? 'inbody.jpg' : file.name;
      final bytes = await file.readAsBytes();
      try {
        await _api.uploadInbody(bytes, name);
      } on AdminRequiredException {
        // 업로드는 관리자만 가능. 비밀번호로 로그인한 뒤 같은 사진을 다시 보냄
        if (!mounted || !await loginAdminWithDialog(context, _api.loginAdmin)) {
          return;
        }
        await _api.uploadInbody(bytes, name);
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('업로드했어요. 잠시 후 기록에 반영돼요')),
      );
      await Future<void>.delayed(const Duration(seconds: 5));
      if (mounted) await _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _records;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('인바디'),
        actions: [
          if (_uploading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              tooltip: '기록지 업로드',
              onPressed: _upload,
              icon: const Icon(Icons.add_a_photo_outlined),
            ),
        ],
      ),
      body: switch ((all, _error)) {
        (null, final String error) => _ErrorState(
          message: error,
          color: _color,
          onRetry: _retry,
        ),
        (null, _) => const Center(child: CircularProgressIndicator()),
        (final List<BodyRecord> all, _) => RefreshIndicator(
          onRefresh: _load,
          child: _buildList(all),
        ),
      },
    );
  }

  Widget _buildList(List<BodyRecord> all) {
    final records = all.where((r) => r.type == _type).toList();
    // 이 측정 종류에 값이 하나라도 있는 지표만 고를 수 있게
    final metrics = [
      for (final m in BodyMetric.values)
        if (records.any((r) => m.valueOf(r) != null)) m,
    ];
    final metric = metrics.contains(_metric) ? _metric : metrics.firstOrNull;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        _Segment(
          values: MeasurementType.values,
          selected: _type,
          labelOf: (t) => '${t.label} ${all.where((r) => r.type == t).length}',
          color: _color,
          onChanged: (t) => setState(() => _type = t),
        ),
        const SizedBox(height: 16),
        if (records.isEmpty)
          _EmptyState(type: _type, color: _color)
        else ...[
          _Summary(records: records, color: _color),
          if (metric != null) ...[
            const SizedBox(height: 20),
            _TrendCard(
              records: records,
              metrics: metrics,
              metric: metric,
              period: _period,
              color: _color,
              onMetricChanged: (m) => setState(() => _metric = m),
              onPeriodChanged: (p) => setState(() => _period = p),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            '전체 기록 ${records.length}개',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          for (final r in records.reversed)
            _RecordTile(key: ValueKey(r.id), record: r),
        ],
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.color,
    required this.onRetry,
  });

  final String message;
  final Color color;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 56, color: color),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              style: FilledButton.styleFrom(backgroundColor: color),
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.type, required this.color});

  final MeasurementType type;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(Icons.accessibility_new, size: 56, color: color),
          const SizedBox(height: 16),
          Text(
            '아직 ${type.label} 기록이 없어요',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            type == MeasurementType.inbody
                ? '오른쪽 위 카메라 버튼으로 기록지를 올려 보세요'
                : '웹에서 기록지를 업로드하면 여기에 보여요',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}

// 가장 최근 기록의 주요 수치와 직전 기록 대비 변화
class _Summary extends StatelessWidget {
  const _Summary({required this.records, required this.color});

  final List<BodyRecord> records;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final latest = records.last;
    final prev = records.length > 1 ? records[records.length - 2] : null;
    final tiles = [
      for (final m in [
        BodyMetric.skeletalMuscle,
        BodyMetric.bodyFatMass,
        BodyMetric.bodyFatPercent,
        BodyMetric.leanMass,
      ])
        if (m.valueOf(latest) != null) m,
    ];
    final bmr = latest.basalMetabolicRate;
    final analysis = BodyAnalysis.tryParse(latest.rawLlmJson);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '최근 측정 · ${formatDate(latest.date)}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 10),
        if (analysis != null) ...[
          BodyAnalysisCard(analysis: analysis, date: latest.date, color: color),
          const SizedBox(height: 10),
        ],
        if (latest.weight != null) ...[
          _WeightHero(latest: latest, prev: prev),
          const SizedBox(height: 10),
        ],
        if (tiles.isNotEmpty)
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.7,
            children: [
              for (final m in tiles)
                _StatTile(metric: m, latest: latest, prev: prev),
            ],
          ),
        if (latest.bmi != null ||
            latest.visceralFatLevel != null ||
            bmr != null) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (latest.bmi != null) _Chip('BMI ${formatNum(latest.bmi!)}'),
              if (latest.visceralFatLevel != null)
                _Chip('내장지방 Lv.${latest.visceralFatLevel}'),
              if (bmr != null) _Chip('기초대사량 ${bmr.round()} kcal'),
            ],
          ),
        ],
      ],
    );
  }
}

// 직전 기록 대비 증감. 지표의 좋은 방향이면 초록, 반대면 빨강, 방향이 없으면 회색
class _Delta extends StatelessWidget {
  const _Delta({required this.metric, required this.latest, this.prev});

  static const good = Color(0xFF5DCAA5);
  static const bad = Color(0xFFF09595);

  final BodyMetric metric;
  final BodyRecord latest;
  final BodyRecord? prev;

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.6);
    final p = prev;
    if (p == null) {
      return Text('첫 기록', style: TextStyle(color: muted, fontSize: 12));
    }
    final now = metric.valueOf(latest), before = metric.valueOf(p);
    // 직전 기록에 이 지표가 없으면 비교하지 않음
    if (now == null || before == null) {
      return Text('', style: TextStyle(color: muted, fontSize: 12));
    }
    final d = now - before;
    if (d.abs() < 0.05) {
      return Text('— 변화 없음', style: TextStyle(color: muted, fontSize: 12));
    }
    final better = metric.higherIsBetter;
    return Text(
      '${d > 0 ? '▲' : '▼'} ${formatNum(d.abs())} ${metric.unit}',
      style: TextStyle(
        color: better == null ? muted : ((d > 0) == better ? good : bad),
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

// 가장 자주 보는 체중은 크게
class _WeightHero extends StatelessWidget {
  const _WeightHero({required this.latest, this.prev});

  final BodyRecord latest;
  final BodyRecord? prev;

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.6);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('체중', style: TextStyle(color: muted, fontSize: 12)),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: formatNum(latest.weight!),
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      TextSpan(
                        text: ' kg',
                        style: TextStyle(fontSize: 14, color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Delta(metric: BodyMetric.weight, latest: latest, prev: prev),
              if (prev != null)
                Text('직전 대비', style: TextStyle(color: muted, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.metric, required this.latest, this.prev});

  final BodyMetric metric;
  final BodyRecord latest;
  final BodyRecord? prev;

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.6);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(metric.label, style: TextStyle(color: muted, fontSize: 12)),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: formatNum(metric.valueOf(latest)!),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                TextSpan(
                  text: ' ${metric.unit}',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
          _Delta(metric: metric, latest: latest, prev: prev),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.8),
          fontSize: 12,
        ),
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.records,
    required this.metrics,
    required this.metric,
    required this.period,
    required this.color,
    required this.onMetricChanged,
    required this.onPeriodChanged,
  });

  final List<BodyRecord> records;
  final List<BodyMetric> metrics;
  final BodyMetric metric;
  final BodyPeriod period;
  final Color color;
  final ValueChanged<BodyMetric> onMetricChanged;
  final ValueChanged<BodyPeriod> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    final withValue = records.where((r) => metric.valueOf(r) != null).toList();
    final shown = period.filter(withValue);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${metric.label} 추이 (${metric.unit})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _Segment(
            values: metrics,
            selected: metric,
            labelOf: (m) => m.label,
            color: color,
            onChanged: onMetricChanged,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: shown.length < 2
                ? Center(
                    child: Text(
                      withValue.length < 2
                          ? '기록이 2개 이상이면 추이를 보여드려요'
                          : '이 기간에는 기록이 부족해요',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  )
                : InbodyTrendChart(
                    records: shown,
                    metric: metric,
                    color: color,
                  ),
          ),
          if (withValue.length >= 2) ...[
            const SizedBox(height: 12),
            _Segment(
              values: BodyPeriod.values,
              selected: period,
              labelOf: (p) => p.label,
              color: color,
              onChanged: onPeriodChanged,
            ),
          ],
        ],
      ),
    );
  }
}

// 한 줄 세그먼트 선택
class _Segment<T> extends StatelessWidget {
  const _Segment({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.color,
    required this.onChanged,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final Color color;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final v in values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: v == selected
                        ? color.withValues(alpha: 0.25)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    labelOf(v),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: v == selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: v == selected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.6),
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

class _RecordTile extends StatelessWidget {
  const _RecordTile({super.key, required this.record});

  final BodyRecord record;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final fatPercent = r.bodyFatPercent;
    final parts = [
      if (r.weight != null) '체중 ${formatNum(r.weight!)}kg',
      if (r.skeletalMuscle != null) '골격근 ${formatNum(r.skeletalMuscle!)}kg',
      if (fatPercent != null) '체지방 ${formatNum(fatPercent)}%',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatDate(r.date),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (parts.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              parts.join(' · '),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
