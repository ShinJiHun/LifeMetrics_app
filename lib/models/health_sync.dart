// 서버 POST /api/health-sync 로 보내는 묶음 (백엔드 HealthSyncRequest 와 같은 모양)
//
// 시간은 오프셋이 붙은 ISO-8601(2026-11-01T12:30:00+09:00), 날짜는 yyyy-MM-dd.
// 단위: 열량 kcal, 거리 m, 영양소 g, 나트륨·칼륨·콜레스테롤·칼슘·철·비타민C mg, 비타민A mcg

class SyncDay {
  const SyncDay({
    required this.date,
    this.steps,
    this.distanceM,
    this.activeKcal,
    this.totalKcal,
    this.exerciseMinutes,
    this.sleepMinutes,
    this.restingHeartRate,
  });

  final DateTime date; // 그날 00:00 (현지 시간)
  final int? steps;
  final double? distanceM;
  final double? activeKcal;
  final double? totalKcal;
  final int? exerciseMinutes;
  final int? sleepMinutes;
  final int? restingHeartRate;

  Map<String, Object?> toJson() => {
    'date': isoDate(date),
    'steps': steps,
    'distanceM': distanceM,
    'activeKcal': activeKcal,
    'totalKcal': totalKcal,
    'exerciseMinutes': exerciseMinutes,
    'sleepMinutes': sleepMinutes,
    'restingHeartRate': restingHeartRate,
  };
}

class SyncNutrition {
  const SyncNutrition({
    required this.id,
    required this.startTime,
    this.mealType,
    this.name,
    this.energyKcal,
    this.carbsG,
    this.proteinG,
    this.fatG,
    this.saturatedFatG,
    this.unsaturatedFatG,
    this.polyunsaturatedFatG,
    this.monounsaturatedFatG,
    this.transFatG,
    this.cholesterolMg,
    this.sodiumMg,
    this.potassiumMg,
    this.fiberG,
    this.sugarG,
    this.vitaminAMcg,
    this.vitaminCMg,
    this.calciumMg,
    this.ironMg,
    this.sourceApp,
  });

  final String id; // 헬스 커넥트 레코드 id. 서버가 이 값으로 덮어씀
  final DateTime startTime;
  final String? mealType; // BREAKFAST / LUNCH / DINNER / SNACK / UNKNOWN
  final String? name;
  final double? energyKcal;
  final double? carbsG;
  final double? proteinG;
  final double? fatG;
  final double? saturatedFatG;
  final double? unsaturatedFatG;
  final double? polyunsaturatedFatG;
  final double? monounsaturatedFatG;
  final double? transFatG;
  final double? cholesterolMg;
  final double? sodiumMg;
  final double? potassiumMg;
  final double? fiberG;
  final double? sugarG;
  final double? vitaminAMcg;
  final double? vitaminCMg;
  final double? calciumMg;
  final double? ironMg;
  final String? sourceApp;

  Map<String, Object?> toJson() => {
    'id': id,
    'startTime': isoWithOffset(startTime),
    'mealType': mealType,
    'name': name,
    'energyKcal': energyKcal,
    'carbsG': carbsG,
    'proteinG': proteinG,
    'fatG': fatG,
    'saturatedFatG': saturatedFatG,
    'unsaturatedFatG': unsaturatedFatG,
    'polyunsaturatedFatG': polyunsaturatedFatG,
    'monounsaturatedFatG': monounsaturatedFatG,
    'transFatG': transFatG,
    'cholesterolMg': cholesterolMg,
    'sodiumMg': sodiumMg,
    'potassiumMg': potassiumMg,
    'fiberG': fiberG,
    'sugarG': sugarG,
    'vitaminAMcg': vitaminAMcg,
    'vitaminCMg': vitaminCMg,
    'calciumMg': calciumMg,
    'ironMg': ironMg,
    'sourceApp': sourceApp,
  };
}

class SyncExercise {
  const SyncExercise({
    required this.id,
    required this.type,
    required this.startTime,
    required this.endTime,
    this.title,
    this.kcal,
    this.distanceM,
    this.avgHeartRate,
    this.sourceApp,
  });

  final String id;
  final String type; // BIKING, WALKING ...
  final String? title;
  final DateTime startTime;
  final DateTime endTime;
  // 세션 시간 동안의 총 소모 칼로리(헬스 커넥트 TotalCaloriesBurned 합).
  // 서버 필드 이름은 activeKcal 이지만 플러그인이 활동 칼로리를 따로 주지 않음
  final double? kcal;
  final double? distanceM;
  final int? avgHeartRate;
  final String? sourceApp;

  int get minutes => endTime.difference(startTime).inMinutes;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    'startTime': isoWithOffset(startTime),
    'endTime': isoWithOffset(endTime),
    'activeKcal': kcal,
    'distanceM': distanceM,
    'avgHeartRate': avgHeartRate,
    'sourceApp': sourceApp,
  };
}

class HealthSyncPayload {
  const HealthSyncPayload({
    this.device,
    this.days = const [],
    this.nutrition = const [],
    this.exercises = const [],
    this.deletedIds = const [],
  });

  final String? device;
  final List<SyncDay> days;
  final List<SyncNutrition> nutrition;
  final List<SyncExercise> exercises;
  final List<String> deletedIds; // 폰에서 지워진 식단 · 운동 레코드 id

  // 읽어 온 수치가 하나라도 있는지. 삭제 목록은 읽기 성공의 증거가 아니라서 보지 않음
  bool get hasData =>
      nutrition.isNotEmpty ||
      exercises.isNotEmpty ||
      days.any(
        (d) =>
            (d.steps ?? 0) != 0 ||
            d.distanceM != null ||
            d.activeKcal != null ||
            d.totalKcal != null ||
            d.exerciseMinutes != null ||
            d.sleepMinutes != null ||
            d.restingHeartRate != null,
      );

  // 식단 · 운동은 [ids] 에 든 것(새로 생기거나 고쳐진 기록)만 남김. 하루 합계(days)는 그대로
  HealthSyncPayload onlyRecords(Set<String> ids) => HealthSyncPayload(
    device: device,
    days: days,
    nutrition: [
      for (final n in nutrition)
        if (ids.contains(n.id)) n,
    ],
    exercises: [
      for (final e in exercises)
        if (ids.contains(e.id)) e,
    ],
    deletedIds: deletedIds,
  );

  HealthSyncPayload withDeleted(List<String> ids) => HealthSyncPayload(
    device: device,
    days: days,
    nutrition: nutrition,
    exercises: exercises,
    deletedIds: ids,
  );

  Map<String, Object?> toJson() => {
    'device': device,
    'days': [for (final d in days) d.toJson()],
    'nutrition': [for (final n in nutrition) n.toJson()],
    'exercises': [for (final e in exercises) e.toJson()],
    'deletedIds': deletedIds,
  };
}

// 서버가 돌려준 반영 건수
class HealthSyncResult {
  const HealthSyncResult({
    required this.days,
    required this.nutrition,
    required this.exercises,
    required this.deleted,
  });

  factory HealthSyncResult.fromJson(Map<String, Object?> j) => HealthSyncResult(
    days: (j['days'] as num?)?.toInt() ?? 0,
    nutrition: (j['nutrition'] as num?)?.toInt() ?? 0,
    exercises: (j['exercises'] as num?)?.toInt() ?? 0,
    deleted: (j['deleted'] as num?)?.toInt() ?? 0,
  );

  final int days;
  final int nutrition;
  final int exercises;
  final int deleted;
}

String _two(int v) => v.toString().padLeft(2, '0');

// 2026-11-01
String isoDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

// 2026-11-01T12:30:00+09:00 (현지 시간 + 오프셋). Dart 의 toIso8601String 은 현지 시간에 오프셋을 붙이지 않음
String isoWithOffset(DateTime t) {
  final l = t.toLocal();
  final o = l.timeZoneOffset;
  final sign = o.isNegative ? '-' : '+';
  final abs = o.abs();
  return '${isoDate(l)}T${_two(l.hour)}:${_two(l.minute)}:${_two(l.second)}'
      '$sign${_two(abs.inHours)}:${_two(abs.inMinutes % 60)}';
}
