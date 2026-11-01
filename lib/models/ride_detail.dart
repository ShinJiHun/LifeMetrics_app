import 'ride.dart';

// GET /api/activity/{id}/summary: 목록 항목(Ride)에 상세 기록이 더 붙은 형태
class RideDetail {
  const RideDetail({
    required this.ride,
    this.elapsedSeconds,
    this.avgSpeed,
    this.maxSpeed,
    this.elevationLoss,
    this.maxHeartRate,
    this.maxPower,
    this.avgCadence,
    this.temperature,
    this.windSpeed,
  });

  final Ride ride;
  final int? elapsedSeconds; // 정지 포함 총 시간
  final double? avgSpeed; // km/h
  final double? maxSpeed; // km/h
  final double? elevationLoss; // 하강고도 (m)
  final double? maxHeartRate; // bpm
  final double? maxPower; // W
  final double? avgCadence; // rpm
  final double? temperature; // °C
  final double? windSpeed; // m/s

  factory RideDetail.fromJson(Map<String, dynamic> json) {
    final weather = json['weather'] as Map?;
    final hasPower = json['hasPower'] != false;
    return RideDetail(
      ride: Ride.fromJson(json),
      elapsedSeconds: (json['elapsedTime'] as num?)?.toInt(),
      avgSpeed: _double(json['avgSpeed']),
      maxSpeed: _double(json['maxSpeed']),
      elevationLoss: _double(json['totalDescent']),
      maxHeartRate: _double(json['maxHeartRate']),
      maxPower: hasPower ? _double(json['maxPower']) : null,
      avgCadence: _double(json['avgCadence']),
      temperature: _double(weather?['temperature']),
      windSpeed: _double(weather?['windSpeed']),
    );
  }
}

// GET /api/activity/{id}/segments 의 구간 기록 1건
class RideSegment {
  const RideSegment({
    required this.id,
    required this.name,
    this.distanceMeters,
    this.elevationGain,
    this.avgGrade,
    this.movingSeconds,
    this.avgHeartRate,
    this.avgPower,
    this.prRank,
  });

  final int id; // effortId
  final String name;
  final double? distanceMeters;
  final double? elevationGain;
  final double? avgGrade; // %
  final int? movingSeconds;
  final double? avgHeartRate;
  final double? avgPower;
  final int? prRank; // 내 기록 중 순위 (1 이 PR), 3위 밖이면 null

  factory RideSegment.fromJson(Map<String, dynamic> json) => RideSegment(
    id: (json['effortId'] as num).toInt(),
    name: (json['segmentName'] as String?)?.trim() ?? '이름 없는 구간',
    distanceMeters: _double(json['distance']),
    elevationGain: _double(json['elevationGain']),
    avgGrade: _double(json['avgGrade']),
    movingSeconds: (json['movingTimeSec'] as num?)?.toInt(),
    avgHeartRate: _double(json['avgHeartRate']),
    avgPower: _double(json['avgPower']),
    prRank: (json['prRank'] as num?)?.toInt(),
  );
}

// GET /api/ai/analysis/activity/{id}: 서버에 저장된 AI 라이딩 분석
class RideAnalysis {
  const RideAnalysis({
    this.summary,
    this.score,
    this.intensity,
    this.pacingGrade,
    this.intensityFactor,
    this.trainingStress,
    this.sections = const [],
    this.highlights = const [],
    this.suggestions = const [],
  });

  final String? summary;
  final int? score; // 0~100
  final String? intensity;
  final String? pacingGrade;
  final double? intensityFactor; // IF
  final int? trainingStress; // TSS
  final List<(String, String)> sections; // (제목, 내용), 빈 항목은 뺌
  final List<String> highlights;
  final List<String> suggestions;

  factory RideAnalysis.fromJson(Map<String, dynamic> json) {
    String? text(String key) {
      final s = (json[key] as String?)?.trim();
      return s == null || s.isEmpty ? null : s;
    }

    List<String> list(String key) => [
      for (final e in json[key] as List? ?? const [])
        if (e is String && e.trim().isNotEmpty) e.trim(),
    ];

    const titles = {
      'pacingAnalysis': '페이스',
      'physiologyAnalysis': '심박 · 파워',
      'cadenceAnalysis': '케이던스',
      'weatherImpact': '날씨',
      'bodyCondition': '몸 상태',
      'recoveryAdvice': '회복',
      'nextRideTip': '다음 라이딩',
    };

    return RideAnalysis(
      summary: text('summary'),
      score: (json['score'] as num?)?.toInt(),
      intensity: text('intensity'),
      pacingGrade: text('pacingGrade'),
      intensityFactor: _double(json['intensityFactor']),
      trainingStress: (json['trainingStress'] as num?)?.toInt(),
      sections: [
        for (final MapEntry(:key, :value) in titles.entries)
          if (text(key) case final body?) (value, body),
      ],
      highlights: list('highlights'),
      suggestions: list('suggestions'),
    );
  }
}

double? _double(Object? v) => (v as num?)?.toDouble();
