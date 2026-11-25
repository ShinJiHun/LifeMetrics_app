// GET /api/bikes 의 자전거 1대 (서버 Bike 엔티티).
// 누적 거리(m) · 이동 시간 · 총 시간(초)은 서버가 라이딩 기록에서 다시 합산해 내려줌
class Bike {
  const Bike({
    required this.id,
    required this.name,
    this.brand,
    this.model,
    this.modelYear,
    this.bikeType,
    this.rideCategory,
    this.frameSize,
    this.frameMaterial,
    this.weightKg,
    this.wheelSize,
    this.groupset,
    this.shiftingType,
    this.speeds,
    this.chainringOuter,
    this.chainringInner,
    this.cassetteLabel,
    this.purchaseDate,
    this.totalDistanceM = 0,
    this.movingSec = 0,
    this.elapsedSec = 0,
    this.isRetired = false,
    this.isDefault = false,
    this.notes,
  });

  factory Bike.fromJson(Map<String, dynamic> j) => Bike(
    id: (j['id'] as num).toInt(),
    name: (j['name'] as String?) ?? (j['model'] as String?) ?? '이름 없는 자전거',
    brand: j['brand'] as String?,
    model: j['model'] as String?,
    modelYear: (j['modelYear'] as num?)?.toInt(),
    bikeType: j['bikeType'] as String?,
    rideCategory: j['rideCategory'] as String?,
    frameSize: j['frameSize'] as String?,
    frameMaterial: j['frameMaterial'] as String?,
    weightKg: (j['weightKg'] as num?)?.toDouble(),
    wheelSize: j['wheelSize'] as String?,
    groupset: j['groupset'] as String?,
    shiftingType: j['shiftingType'] as String?,
    speeds: (j['speeds'] as num?)?.toInt(),
    chainringOuter: (j['chainringOuter'] as num?)?.toInt(),
    chainringInner: (j['chainringInner'] as num?)?.toInt(),
    cassetteLabel: j['cassetteLabel'] as String?,
    purchaseDate: switch (j['purchaseDate']) {
      final String s => DateTime.tryParse(s),
      _ => null,
    },
    totalDistanceM: (j['totalDistance'] as num?)?.toDouble() ?? 0,
    movingSec: (j['totalTime'] as num?)?.toInt() ?? 0,
    elapsedSec: (j['totalElapsedTime'] as num?)?.toInt() ?? 0,
    isRetired: (j['isRetired'] as bool?) ?? false,
    isDefault: (j['isDefault'] as bool?) ?? false,
    notes: j['notes'] as String?,
  );

  final int id;
  final String name;
  final String? brand;
  final String? model;
  final int? modelYear;
  final String? bikeType;
  final String? rideCategory;
  final String? frameSize;
  final String? frameMaterial;
  final double? weightKg;
  final String? wheelSize;
  final String? groupset;
  final String? shiftingType;
  final int? speeds;
  final int? chainringOuter;
  final int? chainringInner;
  final String? cassetteLabel;
  final DateTime? purchaseDate;
  final double totalDistanceM;
  final int movingSec;
  final int elapsedSec;
  final bool isRetired;
  final bool isDefault;
  final String? notes;

  double get totalKm => totalDistanceM / 1000;

  // 이동 시간 기준 평균 속도. 기록이 없으면 null
  double? get avgKmh => movingSec > 0 ? totalKm / (movingSec / 3600) : null;

  // '거스토 · 2026 · 카본'
  String get summary => [
    ?brand,
    if (modelYear != null) '$modelYear',
    ?frameMaterial,
  ].join(' · ');

  // '50/34T'
  String? get chainrings => switch ((chainringOuter, chainringInner)) {
    (final int o, final int i) => '$o/${i}T',
    (final int o, null) => '${o}T',
    _ => null,
  };
}

// GET /api/bikes/{id}/gear-usage 의 한 줄: (앞 톱니, 뒤 톱니, 지형)별 누적 시간 · 거리.
// 톱니 값은 FIT 에서 관측한 실제 톱니 수(T)라 인덱스가 아님
class GearUsage {
  const GearUsage({
    required this.front,
    required this.rear,
    required this.terrain,
    required this.durationSec,
    required this.distanceM,
  });

  factory GearUsage.fromJson(Map<String, dynamic> j) => GearUsage(
    front: (j['frontGear'] as num?)?.toInt() ?? 0,
    rear: (j['rearGear'] as num?)?.toInt() ?? 0,
    terrain: (j['terrain'] as String?) ?? 'FLAT',
    durationSec: (j['durationSec'] as num?)?.toDouble() ?? 0,
    distanceM: (j['distance'] as num?)?.toDouble() ?? 0,
  );

  final int front;
  final int rear;
  final String terrain; // FLAT | UPHILL | DOWNHILL
  final double durationSec;
  final double distanceM;

  static String terrainLabel(String t) => switch (t) {
    'UPHILL' => '오르막',
    'DOWNHILL' => '내리막',
    _ => '평지',
  };
}

// GET /api/bikes/{id}/fits 의 피팅 1건 (최신순)
class BikeFit {
  BikeFit(this.raw) : date = DateTime.parse(raw['fitDate'] as String);

  factory BikeFit.fromJson(Map<String, dynamic> j) => BikeFit(j);

  final Map<String, dynamic> raw;
  final DateTime date;

  String? get fitter => raw['fitter'] as String?;
  String? get notes => raw['notes'] as String?;

  // 화면에 보여줄 (이름, 값) — 값이 있는 것만
  List<(String, String)> get rows {
    String? mm(String k) => switch (raw[k]) {
      final num v => '${_n(v)} mm',
      _ => null,
    };
    String? deg(String k) => switch (raw[k]) {
      final num v => '${_n(v)}°',
      _ => null,
    };
    String? text(String k) => switch (raw[k]) {
      final String v when v.trim().isNotEmpty => v.trim(),
      _ => null,
    };
    return [
      for (final (label, value) in [
        ('안장 높이', mm('saddleHeightMm')),
        ('안장 셋백', mm('saddleSetbackMm')),
        ('안장 각도', deg('saddleTiltDeg')),
        ('안장', text('saddleModel')),
        ('리치', mm('reachMm')),
        ('드롭', mm('dropMm')),
        ('스템 길이', mm('stemLengthMm')),
        ('스템 각도', deg('stemAngleDeg')),
        ('스페이서', mm('spacerMm')),
        ('핸들바 폭', mm('handlebarWidthMm')),
        ('크랭크 길이', mm('crankLengthMm')),
        ('클릿 (왼쪽)', text('cleatLeft')),
        ('클릿 (오른쪽)', text('cleatRight')),
      ])
        if (value != null) (label, value),
    ];
  }

  static String _n(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}
