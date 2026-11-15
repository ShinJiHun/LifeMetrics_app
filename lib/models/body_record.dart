// 서버 user_body_record.measurement_type
enum MeasurementType {
  inbody('INBODY', '인바디'),
  fitdays('FITDAYS', 'FitDays');

  const MeasurementType(this.code, this.label);

  final String code;
  final String label;

  static MeasurementType? fromCode(String? code) {
    for (final t in values) {
      if (t.code == code) return t;
    }
    return null;
  }
}

// GET /api/body/records 의 기록 1건. 측정 종류에 따라 비는 값이 많아 전부 nullable
class BodyRecord {
  const BodyRecord({
    required this.id,
    required this.date,
    required this.type,
    this.weight,
    this.skeletalMuscle,
    this.bodyFatMass,
    this.fatFreeMass,
    this.bodyFatPercentage,
    this.bmi,
    this.visceralFatLevel,
    this.basalMetabolicRate,
    this.rawLlmJson,
  });

  final int id;
  final DateTime date;
  final MeasurementType type;
  final double? weight; // 체중 (kg)
  final double? skeletalMuscle; // 골격근량 (kg)
  final double? bodyFatMass; // 체지방량 (kg)
  final double? fatFreeMass; // 제지방량 (kg), 기록지 값
  final double? bodyFatPercentage; // 체지방률 (%), 기록지 값
  final double? bmi;
  final int? visceralFatLevel; // 내장지방 레벨
  final double? basalMetabolicRate; // 기초대사량 (kcal)
  final String? rawLlmJson; // 서버에 저장된 AI 분석 결과

  // 기록지 값을 우선하고, 없으면 체중과 체지방량으로 계산
  double? get bodyFatPercent {
    if (bodyFatPercentage != null) return bodyFatPercentage;
    final w = weight, f = bodyFatMass;
    return w == null || f == null || w <= 0 ? null : f / w * 100;
  }

  double? get leanMass {
    if (fatFreeMass != null) return fatFreeMass;
    final w = weight, f = bodyFatMass;
    return w == null || f == null ? null : w - f;
  }

  factory BodyRecord.fromJson(Map<String, dynamic> json) => BodyRecord(
    id: (json['id'] as num).toInt(),
    date: DateTime.parse(json['recordDate'] as String),
    type:
        MeasurementType.fromCode(json['measurementType'] as String?) ??
        MeasurementType.inbody,
    weight: _double(json['weight']),
    skeletalMuscle: _double(json['skeletalMuscleMass']),
    bodyFatMass: _double(json['bodyFatMass']),
    fatFreeMass: _double(json['fatFreeMass']),
    bodyFatPercentage: _double(json['bodyFatPercentage']),
    bmi: _double(json['bmi']),
    visceralFatLevel: (json['visceralFatLevel'] as num?)?.toInt(),
    basalMetabolicRate: _double(json['basalMetabolicRate']),
    rawLlmJson: json['rawLlmJson'] as String?,
  );

  static double? _double(Object? v) => (v as num?)?.toDouble();
}

// 추이 차트에서 한 번에 하나씩 보여줄 지표
enum BodyMetric {
  weight('체중', 'kg', null),
  skeletalMuscle('골격근량', 'kg', true),
  bodyFatMass('체지방량', 'kg', false),
  bodyFatPercent('체지방률', '%', false),
  leanMass('제지방량', 'kg', true);

  const BodyMetric(this.label, this.unit, this.higherIsBetter);

  final String label;
  final String unit;
  // 늘어나는 게 좋은 지표인지. 체중처럼 목표에 따라 다른 건 null
  final bool? higherIsBetter;

  double? valueOf(BodyRecord r) => switch (this) {
    weight => r.weight,
    skeletalMuscle => r.skeletalMuscle,
    bodyFatMass => r.bodyFatMass,
    bodyFatPercent => r.bodyFatPercent,
    leanMass => r.leanMass,
  };
}

// 추이 차트 기간. 마지막 측정일 기준으로 거슬러 올라감
enum BodyPeriod {
  months3('3개월', 3),
  months6('6개월', 6),
  year1('1년', 12),
  all('전체', null);

  const BodyPeriod(this.label, this.months);

  final String label;
  final int? months;

  List<BodyRecord> filter(List<BodyRecord> records) {
    final m = months;
    if (m == null || records.isEmpty) return records;
    final last = records.last.date;
    final from = DateTime(last.year, last.month - m, last.day);
    return records.where((r) => !r.date.isBefore(from)).toList();
  }
}

// GET /api/body/goals/current + /api/body/weight-loss 에서 감량 계산에 필요한 값만
class CutBasis {
  const CutBasis({
    this.weight,
    this.weightDate,
    this.bmr,
    this.bmrEstimated = false,
    this.targetWeight,
    this.targetDate,
    this.ftp,
  });

  factory CutBasis.fromJson(
    Map<String, dynamic> goal,
    Map<String, dynamic> loss,
  ) {
    final g = goal['goal'] as Map?;
    final cur = goal['current'] as Map?;
    DateTime? date(Object? v) => v is String ? DateTime.tryParse(v) : null;
    return CutBasis(
      weight:
          (cur?['weight'] as num?)?.toDouble() ??
          (loss['weight'] as num?)?.toDouble(),
      weightDate: date(cur?['weightDate']) ?? date(loss['recordDate']),
      bmr: (loss['basalMetabolicRate'] as num?)?.toDouble(),
      bmrEstimated: loss['bmrEstimated'] == true,
      targetWeight: (g?['targetWeight'] as num?)?.toDouble(),
      targetDate: date(g?['targetDate']),
      ftp: (goal['ftp'] as num?)?.toInt(),
    );
  }

  final double? weight; // kg
  final DateTime? weightDate;
  final double? bmr; // 기초대사량 kcal
  final bool bmrEstimated; // 기록지 값이 아니라 서버가 추정한 값
  final double? targetWeight;
  final DateTime? targetDate;
  final int? ftp; // W, 실내 사이클 강도 계산용
}
