import 'package:flutter/material.dart';

import '../../../models/athlete_section.dart';
import '../../../models/bike.dart';
import '../../../services/api_client.dart';
import '../../../services/bike_api.dart';
import '../../../utils/format.dart';
import '../../../widgets/status_message.dart';

// 장비 기록 > 내 자전거: 쓰는 자전거 → 은퇴한 자전거 순. 누르면 사양 · 누적 · 기어 사용 · 피팅
class BikeListScreen extends StatefulWidget {
  const BikeListScreen({super.key, this.api});

  final BikeApi? api;

  @override
  State<BikeListScreen> createState() => _BikeListScreenState();
}

class _BikeListScreenState extends State<BikeListScreen> {
  static final _color = AthleteSection.gear.color;

  late final BikeApi _api = widget.api ?? BikeApi();

  List<Bike>? _bikes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bikes = await _api.fetchBikes();
      if (mounted) {
        setState(() {
          _bikes = bikes;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _retry() async {
    setState(() {
      _bikes = null;
      _error = null;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('내 자전거'),
      ),
      body: switch ((_bikes, _error)) {
        (null, final String error) => StatusMessage(
          icon: Icons.cloud_off,
          title: error,
          color: _color,
          action: '다시 시도',
          onAction: _retry,
        ),
        (null, _) => const Center(child: CircularProgressIndicator()),
        (final List<Bike> bikes, _) when bikes.isEmpty => StatusMessage(
          icon: Icons.pedal_bike,
          title: '등록된 자전거가 없어요',
          detail: '웹(ride.tho881.me) 장비 화면에서 자전거를 추가하면 여기 보여요',
          color: _color,
        ),
        (final List<Bike> bikes, _) => RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              for (final b in bikes.where((b) => !b.isRetired))
                _BikeCard(bike: b, color: _color, onTap: () => _open(b)),
              if (bikes.any((b) => b.isRetired)) ...[
                const _Title('은퇴한 자전거'),
                for (final b in bikes.where((b) => b.isRetired))
                  _BikeCard(bike: b, color: _color, onTap: () => _open(b)),
              ],
            ],
          ),
        ),
      },
    );
  }

  void _open(Bike b) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => BikeDetailScreen(bike: b, api: _api, color: _color),
    ),
  );
}

class _BikeCard extends StatelessWidget {
  const _BikeCard({
    required this.bike,
    required this.color,
    required this.onTap,
  });

  final Bike bike;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.55);
    final b = bike;
    return Card(
      color: Colors.white.withValues(alpha: b.isRetired ? 0.03 : 0.06),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.pedal_bike, color: b.isRetired ? muted : color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      b.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (b.isDefault)
                    _Badge(text: '기본', color: color)
                  else if (b.isRetired)
                    _Badge(text: '은퇴', color: muted),
                ],
              ),
              if (b.summary.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 34),
                  child: Text(b.summary, style: TextStyle(color: muted)),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Stat(
                    label: '누적 거리',
                    value: '${formatThousands(b.totalKm)} km',
                  ),
                  _Stat(label: '이동 시간', value: formatDuration(b.movingSec)),
                  _Stat(
                    label: '평균 속도',
                    value: b.avgKmh == null
                        ? '-'
                        : '${formatNum(b.avgKmh!)} km/h',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 자전거 한 대: 누적 · 사양 · 기어 사용 · 피팅
class BikeDetailScreen extends StatefulWidget {
  const BikeDetailScreen({
    super.key,
    required this.bike,
    required this.api,
    required this.color,
  });

  final Bike bike;
  final BikeApi api;
  final Color color;

  @override
  State<BikeDetailScreen> createState() => _BikeDetailScreenState();
}

class _BikeDetailScreenState extends State<BikeDetailScreen> {
  List<GearUsage>? _gears;
  List<BikeFit>? _fits;
  String? _gearError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.bike.id;
    try {
      final gears = await widget.api.fetchGearUsage(id);
      if (mounted) setState(() => _gears = gears);
    } on ApiException catch (e) {
      if (mounted) setState(() => _gearError = e.message);
    }
    try {
      final fits = await widget.api.fetchFits(id);
      if (mounted) setState(() => _fits = fits);
    } on ApiException {
      if (mounted) setState(() => _fits = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bike;
    final color = widget.color;
    final specs = <(String, String?)>[
      ('브랜드 · 모델', [?b.brand, ?b.model].join(' ').trim()),
      ('연식', b.modelYear?.toString()),
      ('종류', [?b.bikeType, ?b.rideCategory].join(' · ')),
      ('프레임', [?b.frameSize, ?b.frameMaterial].join(' · ')),
      ('무게', b.weightKg == null ? null : '${formatNum(b.weightKg!)} kg'),
      ('휠', b.wheelSize),
      (
        '구동계',
        [
          ?b.groupset,
          ?b.shiftingType,
          if (b.speeds != null) '${b.speeds}단',
        ].join(' · '),
      ),
      ('체인링', b.chainrings),
      ('카세트', b.cassetteLabel),
      (
        '구매일',
        b.purchaseDate == null ? null : formatDate(b.purchaseDate!),
      ),
      ('메모', b.notes),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(b.name),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _Panel(
            child: Row(
              children: [
                _Stat(
                  label: '누적 거리',
                  value: '${formatThousands(b.totalKm)} km',
                ),
                _Stat(label: '이동 시간', value: formatDuration(b.movingSec)),
                _Stat(label: '총 시간', value: formatDuration(b.elapsedSec)),
              ],
            ),
          ),
          const _Title('사양'),
          _Panel(
            child: Column(
              children: [
                for (final (label, value) in specs)
                  if (value != null && value.isNotEmpty) _Row(label, value),
              ],
            ),
          ),
          const _Title('기어 사용'),
          switch ((_gears, _gearError)) {
            (_, final String error) => _Panel(child: Text(error)),
            (null, _) => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            (final List<GearUsage> g, _) => _GearPanel(usage: g, color: color),
          },
          const _Title('피팅'),
          switch (_fits) {
            null => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            final List<BikeFit> fits when fits.isEmpty => _Panel(
              child: Text(
                '피팅 기록이 없어요. 웹 장비 화면에서 입력하면 여기 보여요',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
              ),
            ),
            final List<BikeFit> fits => Column(
              children: [
                for (final (i, f) in fits.indexed)
                  _FitPanel(fit: f, latest: i == 0, color: color),
              ],
            ),
          },
        ],
      ),
    );
  }
}

// 기어 사용: 체인링별 시간 비율, 지형별 이너 비율, 많이 쓴 조합
class _GearPanel extends StatelessWidget {
  const _GearPanel({required this.usage, required this.color});

  final List<GearUsage> usage;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.55);
    final total = usage.fold<double>(0, (s, g) => s + g.durationSec);
    if (usage.isEmpty || total <= 0) {
      return _Panel(
        child: Text(
          '기어 기록이 없어요 (전동 변속기 FIT 기록이 있어야 해요)',
          style: TextStyle(color: muted),
        ),
      );
    }

    // 체인링별 시간 (큰 톱니가 아우터)
    final byFront = <int, double>{};
    for (final g in usage) {
      byFront[g.front] = (byFront[g.front] ?? 0) + g.durationSec;
    }
    final fronts = byFront.keys.toList()..sort((a, b) => b.compareTo(a));
    final inner = fronts.length > 1 ? fronts.last : null;

    // 지형별 이너 비율
    final terrains = ['FLAT', 'UPHILL', 'DOWNHILL'];
    double share(String t, {int? front}) {
      final all = usage
          .where((g) => g.terrain == t)
          .fold<double>(0, (s, g) => s + g.durationSec);
      if (all <= 0) return -1;
      final part = usage
          .where((g) => g.terrain == t && (front == null || g.front == front))
          .fold<double>(0, (s, g) => s + g.durationSec);
      return part / all;
    }

    // 많이 쓴 조합 (지형 합산)
    final combos = <(int, int), double>{};
    for (final g in usage) {
      combos[(g.front, g.rear)] =
          (combos[(g.front, g.rear)] ?? 0) + g.durationSec;
    }
    final top = combos.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    String pct(double r) => '${(r * 100).round()}%';

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('체인링별 시간', style: TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 6),
          for (final f in fronts)
            _Bar(
              label: '${f}T',
              ratio: byFront[f]! / total,
              trailing: pct(byFront[f]! / total),
              color: f == inner ? color.withValues(alpha: 0.6) : color,
            ),
          if (inner != null) ...[
            const SizedBox(height: 14),
            Text(
              '지형별 이너(${inner}T) 비율',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 6),
            for (final t in terrains)
              if (share(t) >= 0)
                _Bar(
                  label: GearUsage.terrainLabel(t),
                  ratio: share(t, front: inner),
                  trailing: pct(share(t, front: inner)),
                  color: color.withValues(alpha: 0.6),
                ),
          ],
          const SizedBox(height: 14),
          Text('많이 쓴 조합', style: TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 6),
          for (final e in top.take(6))
            _Bar(
              label: '${e.key.$1}×${e.key.$2}',
              ratio: e.value / top.first.value,
              trailing:
                  '${pct(e.value / total)} · ${formatDuration(e.value.round())}',
              color: color,
            ),
        ],
      ),
    );
  }
}

class _FitPanel extends StatelessWidget {
  const _FitPanel({
    required this.fit,
    required this.latest,
    required this.color,
  });

  final BikeFit fit;
  final bool latest;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.55);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatDate(fit.date),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (latest) _Badge(text: '최신', color: color),
            ],
          ),
          if (fit.fitter case final fitter?)
            Text(fitter, style: TextStyle(color: muted)),
          const SizedBox(height: 6),
          for (final (label, value) in fit.rows) _Row(label, value),
          if (fit.notes case final notes? when notes.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(notes, style: TextStyle(color: muted)),
            ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.ratio,
    required this.trailing,
    required this.color,
  });

  final String label;
  final double ratio; // 0~1
  final String trailing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 64, child: Text(label)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio.clamp(0, 1).toDouble(),
                minHeight: 10,
                color: color,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 104,
            child: Text(
              trailing,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ),
        ],
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
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
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
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
