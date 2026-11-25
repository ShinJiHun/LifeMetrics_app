import 'package:flutter/material.dart';

import '../../../models/athlete_section.dart';
import '../../../models/health_checkup.dart';
import '../../../services/api_client.dart';
import '../../../services/health_checkup_api.dart';
import '../../../utils/format.dart';
import '../../../widgets/admin_login_dialog.dart';

// 신체 기록 > 건강검진: 서버에 저장된 국가건강검진 결과(웹에서 PDF 로 올림)를 봄.
// 맨 위 최근 검진 요약 → 주요 수치(지난 검진 대비 변화) → 검진 기록 목록.
// 서버 조회가 관리자 전용이라 처음에 비밀번호를 물음
class HealthCheckupScreen extends StatefulWidget {
  const HealthCheckupScreen({super.key, this.api});

  final HealthCheckupApi? api;

  @override
  State<HealthCheckupScreen> createState() => _HealthCheckupScreenState();
}

class _HealthCheckupScreenState extends State<HealthCheckupScreen> {
  static final _color = AthleteSection.body.color;
  static final _muted = Colors.white.withValues(alpha: 0.55);

  late final HealthCheckupApi _api = widget.api ?? HealthCheckupApi();

  List<HealthCheckup>? _items;
  bool _loading = true;
  bool _needsLogin = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(askLogin: true);
  }

  Future<void> _load({bool askLogin = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _api.fetchAll();
      if (!mounted) return;
      setState(() {
        _items = items;
        _needsLogin = false;
        _loading = false;
      });
    } on AdminRequiredException {
      if (!mounted) return;
      setState(() {
        _needsLogin = true;
        _loading = false;
      });
      // 화면을 처음 열 때는 바로 비밀번호를 물음
      if (askLogin) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _login());
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _login() async {
    if (!mounted) return;
    if (await loginAdminWithDialog(context, _api.loginAdmin)) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('건강검진'),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_needsLogin) {
      return _Message(
        icon: Icons.lock_outline,
        title: '관리자 로그인이 필요해요',
        action: '로그인',
        color: _color,
        onAction: _login,
      );
    }
    if (_error case final error?) {
      return _Message(
        icon: Icons.error_outline,
        title: error,
        action: '다시 시도',
        color: _color,
        onAction: _load,
      );
    }
    final items = _items ?? const [];
    if (items.isEmpty) {
      return _Message(
        icon: Icons.medical_information_outlined,
        title: '저장된 건강검진이 없어요',
        detail: '웹(ride.tho881.me)에서 검진 결과통보서 PDF를 올리면 여기에 보여요',
        action: '새로고침',
        color: _color,
        onAction: _load,
      );
    }

    final latest = items.first;
    final previous = items.length > 1 ? items[1] : null;
    final metrics = [
      for (final m in CheckupMetric.all)
        if (latest.value(m.key) != null) m,
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _LatestCard(
            item: latest,
            color: _color,
            onTap: () => _openDetail(latest),
          ),
          if (metrics.isNotEmpty) ...[
            const SizedBox(height: 20),
            _SectionTitle(
              '주요 수치',
              trailing: previous == null
                  ? null
                  : '${formatDate(previous.date)} 대비',
            ),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  for (final (i, m) in metrics.indexed) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    _MetricRow(
                      metric: m,
                      latest: latest,
                      previous: previous,
                      onTap: () => _openHistory(m, items),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          _SectionTitle('검진 기록', trailing: '${items.length}회'),
          for (final c in items)
            Card(
              color: Colors.white.withValues(alpha: 0.05),
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: ListTile(
                leading: Icon(Icons.event_note, color: _color),
                title: Text(
                  formatDate(c.date),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  [?c.place, ?c.overall].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _muted),
                ),
                trailing: Icon(Icons.chevron_right, color: _muted),
                onTap: () => _openDetail(c),
              ),
            ),
        ],
      ),
    );
  }

  void _openDetail(HealthCheckup c) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => HealthCheckupDetailScreen(item: c, color: _color),
    ),
  );

  // 수치 하나를 검진별로 모아 봄 (최근이 위)
  void _openHistory(CheckupMetric m, List<HealthCheckup> items) {
    final rows = [
      for (final c in items)
        if (c.value(m.key) case final v?) (c, v),
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1A38),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          children: [
            Text(
              '${m.label} 추이',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            for (final (c, v) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(formatDate(c.date))),
                    Text(
                      '${m.format(v)} ${m.unit}'.trim(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (m.resultKey != null) ...[
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 72,
                        child: Text(
                          c.text(m.resultKey!) ?? '',
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _muted, fontSize: 12),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LatestCard extends StatelessWidget {
  const _LatestCard({
    required this.item,
    required this.color,
    required this.onTap,
  });

  final HealthCheckup item;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.55);
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('최근 검진', style: TextStyle(color: muted, fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                formatDate(item.date),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (item.place case final place?)
                Text(place, style: TextStyle(color: muted)),
              if (item.overall case final overall?) ...[
                const SizedBox(height: 12),
                Text(
                  '종합판정',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                Text(
                  overall,
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (item.suspected case final suspected?) ...[
                const SizedBox(height: 8),
                Text(
                  '의심 질환: $suspected',
                  style: TextStyle(color: Colors.amber.shade200),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// 수치 한 줄: 이름 · 판정 | 값 · 지난 검진 대비 변화
class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.metric,
    required this.latest,
    required this.previous,
    required this.onTap,
  });

  final CheckupMetric metric;
  final HealthCheckup latest;
  final HealthCheckup? previous;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.55);
    final value = latest.value(metric.key)!;
    final before = previous?.value(metric.key);
    final result = metric.resultKey == null
        ? null
        : latest.text(metric.resultKey!);

    String? change;
    if (before != null) {
      final d = value - before;
      final s = metric.format(d.abs());
      change = double.parse(s) == 0 ? '변화 없음' : '${d > 0 ? '▲' : '▼'} $s';
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(metric.label),
                  if (result != null)
                    Text(result, style: TextStyle(color: muted, fontSize: 12)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${metric.format(value)} ${metric.unit}'.trim(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (change != null)
                  Text(change, style: TextStyle(color: muted, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// 검진 1건 전체: 영역별로 값이 있는 칸만
class HealthCheckupDetailScreen extends StatelessWidget {
  const HealthCheckupDetailScreen({
    super.key,
    required this.item,
    required this.color,
  });

  final HealthCheckup item;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = item;
    String? n(String key, String unit, {int decimals = 0}) {
      final v = c.value(key);
      return v == null ? null : '${v.toStringAsFixed(decimals)} $unit'.trim();
    }

    String? yes(String key) => c.flag(key) == true ? '필요' : null;

    final vision = [
      if (c.value('visionLeft') case final l?) '좌 $l',
      if (c.value('visionRight') case final r?) '우 $r',
      if (c.flag('visionCorrected') == true) '(교정)',
    ].join(' ');
    final hearing = [
      if (c.text('hearingLeft') case final l?) '좌 $l',
      if (c.text('hearingRight') case final r?) '우 $r',
    ].join(' ');
    final bp = c.value('systolicBp') != null && c.value('diastolicBp') != null
        ? '${c.value('systolicBp')!.round()}/${c.value('diastolicBp')!.round()} mmHg'
        : null;

    final sections = <(String, List<(String, String?)>)>[
      (
        '판정 · 소견',
        [
          ('종합판정', c.overall),
          ('의심 질환', c.suspected),
          ('유질환', c.text('existingDisease')),
          ('추가 검사', c.text('extraExams')),
          ('생활습관 권고', c.text('lifestyleAdvice')),
          ('기타 권고', c.text('etcAdvice')),
        ],
      ),
      (
        '계측',
        [
          ('신장', n('heightCm', 'cm', decimals: 1)),
          ('체중', n('weightKg', 'kg', decimals: 1)),
          ('BMI', n('bmi', '', decimals: 1)),
          ('비만도', c.text('bmiGrade')),
          ('허리둘레', n('waistCm', 'cm', decimals: 1)),
          ('허리둘레 판정', c.text('waistResult')),
          ('시력', vision.isEmpty ? null : vision),
          ('청력', hearing.isEmpty ? null : hearing),
          ('청력 판정', c.text('hearingResult')),
        ],
      ),
      (
        '혈압',
        [('혈압', bp), ('판정', c.text('bpResult'))],
      ),
      (
        '혈액',
        [
          ('혈색소', n('hemoglobin', 'g/dL', decimals: 1)),
          ('빈혈 판정', c.text('anemiaResult')),
          ('공복혈당', n('fastingBloodSugar', 'mg/dL')),
          ('당뇨 판정', c.text('diabetesResult')),
          ('총콜레스테롤', n('totalCholesterol', 'mg/dL')),
          ('HDL 콜레스테롤', n('hdlCholesterol', 'mg/dL')),
          ('LDL 콜레스테롤', n('ldlCholesterol', 'mg/dL')),
          ('중성지방', n('triglyceride', 'mg/dL')),
          ('이상지질혈증 판정', c.text('lipidResult')),
          ('혈청 크레아티닌', n('serumCreatinine', 'mg/dL', decimals: 2)),
          ('eGFR', n('egfr', 'mL/min')),
          ('신장 판정', c.text('kidneyResult')),
          ('AST', n('ast', 'U/L')),
          ('ALT', n('alt', 'U/L')),
          ('감마지티피', n('ggt', 'U/L')),
          ('간 판정', c.text('liverResult')),
        ],
      ),
      (
        '소변 · 영상',
        [
          ('요단백', c.text('urineProteinResult')),
          ('흉부방사선', c.text('chestXrayResult')),
        ],
      ),
      (
        '추가 검사',
        [
          ('B형간염', c.text('hepBResult')),
          ('C형간염', c.text('hepCResult')),
          ('우울증', c.text('depressionResult')),
          ('정신건강', c.text('psychosisResult')),
          ('인지기능', c.text('cognitiveResult')),
          ('골밀도', c.text('boneDensityResult')),
          ('배뇨장애', c.text('urinationResult')),
        ],
      ),
      (
        '생활습관',
        [
          ('과거병력', c.text('pastHistory')),
          ('복용 약', c.text('medication')),
          ('금연', yes('needSmokingCessation')),
          ('절주', yes('needDrinkingReduction')),
          ('신체활동', yes('needPhysicalActivity')),
          ('근력운동', yes('needStrengthExercise')),
        ],
      ),
    ];

    final muted = Colors.white.withValues(alpha: 0.55);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(formatDate(c.date)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (c.place case final place?)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                [place, ?c.text('checkupDoctor')].join(' · '),
                style: TextStyle(color: muted),
              ),
            ),
          for (final (title, rows) in sections)
            if (rows.any((r) => r.$2 != null)) ...[
              _SectionTitle(title),
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    for (final (label, value) in rows)
                      if (value != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 112,
                                child: Text(
                                  label,
                                  style: TextStyle(color: muted),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  value,
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.action,
    required this.color,
    required this.onAction,
    this.detail,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final String action;
  final Color color;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.55);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: muted),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(backgroundColor: color),
              child: Text(action),
            ),
          ],
        ),
      ),
    );
  }
}
