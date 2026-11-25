import 'ride.dart' show decodePolyline;

// GET /api/randonneuring/results 의 공식 참가 기록 1건 (KORA 기록 가져오기)
class RandoResult {
  const RandoResult({
    required this.id,
    required this.date,
    required this.eventType,
    required this.name,
    required this.distanceKm,
    required this.finished,
    this.permanentNo,
    this.ridingTimeSec,
    this.homologationNo,
    this.notes,
  });

  factory RandoResult.fromJson(Map<String, dynamic> j) => RandoResult(
    id: (j['id'] as num).toInt(),
    date: DateTime.parse(j['eventDate'] as String),
    eventType: (j['eventType'] as String?) ?? 'BREVET',
    name: (j['eventName'] as String?) ?? '',
    distanceKm: (j['distanceKm'] as num?)?.toInt() ?? 0,
    finished: j['status'] == 'FINISHED',
    permanentNo: j['permanentNo'] as String?,
    ridingTimeSec: (j['ridingTimeSec'] as num?)?.toInt(),
    homologationNo: j['homologationNo'] as String?,
    notes: j['notes'] as String?,
  );

  final int id;
  final DateTime date;
  final String eventType; // BREVET | PERMANENT | FLECHE | POPULAIRE
  final String name;
  final int distanceKm;
  final bool finished; // false 면 DNF
  final String? permanentNo;
  final int? ridingTimeSec;
  final String? homologationNo;
  final String? notes;

  String get typeLabel => switch (eventType) {
    'PERMANENT' => '퍼머넌트',
    'FLECHE' => '플레쉬',
    'POPULAIRE' => '포퓰레르',
    _ => '브레베',
  };

  // 표준 거리 구간 (210km 브레베도 200 으로). 표준 거리보다 짧으면 null
  int? get nominalKm {
    int? best;
    for (final d in standardDistances) {
      if (distanceKm >= d) best = d;
    }
    return best;
  }

  static const standardDistances = [200, 300, 400, 600, 1000, 1200];
}

// 기록 묶음에서 뽑은 요약
class RandoCareer {
  RandoCareer(List<RandoResult> items, {DateTime? now})
    : starts = items.length,
      finishes = items.where((r) => r.finished).length,
      finishedKm = items
          .where((r) => r.finished)
          .fold(0, (s, r) => s + r.distanceKm),
      longest = items
          .where((r) => r.finished)
          .fold<RandoResult?>(
            null,
            (best, r) =>
                best == null || r.distanceKm > best.distanceKm ? r : best,
          ),
      year = (now ?? DateTime.now()).year {
    // 올해 완주한 브레베의 표준 거리 (슈퍼 랜도너 시리즈 200 · 300 · 400 · 600 확인용)
    for (final r in items) {
      if (r.finished &&
          r.eventType == 'BREVET' &&
          r.date.year == year &&
          r.nominalKm != null) {
        yearBrevets.add(r.nominalKm!);
      }
    }
  }

  final int starts;
  final int finishes;
  final int finishedKm;
  final RandoResult? longest;
  final int year;
  final Set<int> yearBrevets = {};

  static const srSeries = [200, 300, 400, 600];
  bool get yearSr => srSeries.every(yearBrevets.contains);
}

// GET /api/brevet/schedule 의 일정 1건 (협회 일정 페이지를 읽은 값이라 날짜 형식이 제각각)
class BrevetEvent {
  const BrevetEvent({
    required this.date,
    required this.region,
    required this.name,
    required this.distance,
    required this.open,
  });

  factory BrevetEvent.fromJson(Map<String, dynamic> j) => BrevetEvent(
    date: (j['date'] as String?) ?? '',
    region: (j['region'] as String?) ?? '',
    name: (j['name'] as String?) ?? '',
    distance: int.tryParse((j['distance'] as String?) ?? ''),
    open: (j['hasLink'] as bool?) ?? false,
  );

  final String date; // "3월07일", "01.10" ...
  final String region;
  final String name;
  final int? distance; // 플레쉬 등은 null
  final bool open; // 신청 링크가 있음

  // 거리 필터용 구간: 200 · 300 · 400 · 600 · 1000+ · 기타
  String get bucket => switch (distance) {
    200 || 300 || 400 || 600 => '$distance',
    final int d when d >= 1000 => '1000+',
    _ => '기타',
  };
}

// GET /api/permanents 의 코스 1행 (gpx 파일이 여럿이면 같은 번호로 여러 행)
class PermanentCourse {
  PermanentCourse({
    required this.no,
    required this.name,
    this.distanceKm,
    this.timeLimit,
    this.gpxLabel,
    this.polyline,
  });

  factory PermanentCourse.fromJson(Map<String, dynamic> j) => PermanentCourse(
    no: (j['permanentNo'] as String?) ?? '',
    name: (j['name'] as String?) ?? '',
    distanceKm: (j['distanceKm'] as num?)?.toInt(),
    timeLimit: j['timeLimitHm'] as String?,
    gpxLabel: j['gpxLabel'] as String?,
    polyline: j['polyline'] as String?,
  );

  final String no; // PT-01
  final String name;
  final int? distanceKm;
  final String? timeLimit; // HH:MM
  final String? gpxLabel;
  final String? polyline;

  late final List<(double, double)> route = decodePolyline(polyline ?? '');

  bool matches(String q) {
    final s = q.trim().toLowerCase();
    return s.isEmpty ||
        no.toLowerCase().contains(s) ||
        name.toLowerCase().contains(s);
  }
}
