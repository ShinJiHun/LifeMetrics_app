// 헬스 커넥트(삼성헬스가 동기화한 데이터)에서 읽은 하루치 요약
class DailyHealth {
  const DailyHealth({
    required this.day,
    this.steps,
    this.activeKcal,
    this.sleepMinutes,
    this.restingHr,
    this.avgHr,
  });

  final DateTime day; // 그날 00:00 (현지 시간)
  final int? steps;
  final double? activeKcal;
  final int? sleepMinutes; // 그날 아침에 끝난 수면 기준
  final int? restingHr;
  final int? avgHr;

  bool get isEmpty =>
      steps == null &&
      activeKcal == null &&
      sleepMinutes == null &&
      restingHr == null &&
      avgHr == null;
}

// 최근 며칠의 일별 요약과 가장 최근 체성분
class HealthSnapshot {
  const HealthSnapshot({
    required this.days,
    this.weight,
    this.bodyFat,
    this.weighedAt,
    this.yesterdayMeals = const [],
    this.mealsAuthorized = true,
    this.sources = const {},
  });

  final List<DailyHealth> days; // 날짜 오름차순, 마지막이 오늘
  final double? weight; // kg
  final double? bodyFat; // %
  final DateTime? weighedAt;
  final List<Meal> yesterdayMeals; // 시간 오름차순
  final bool mealsAuthorized; // 식사(영양) 읽기 권한
  final Set<String> sources; // 데이터를 쓴 앱 패키지 이름

  DailyHealth get today => days.last;

  bool get isEmpty =>
      weight == null && yesterdayMeals.isEmpty && days.every((d) => d.isEmpty);
}

enum MealKind {
  breakfast('아침'),
  lunch('점심'),
  dinner('저녁'),
  snack('간식'),
  unknown('기타');

  const MealKind(this.label);

  final String label;

  // 헬스 커넥트 플러그인이 주는 BREAKFAST / LUNCH / DINNER / SNACK / UNKNOWN
  static MealKind fromHealth(String? s) => switch (s) {
    'BREAKFAST' => breakfast,
    'LUNCH' => lunch,
    'DINNER' => dinner,
    'SNACK' => snack,
    _ => unknown,
  };
}

// 음식 한 건. 영양소는 기록한 앱이 넣어준 것만 있음
class Meal {
  const Meal({
    required this.at,
    required this.type,
    this.name,
    this.calories,
    this.protein,
    this.fat,
    this.carbs,
  });

  final DateTime at;
  final MealKind type;
  final String? name;
  final double? calories; // kcal
  final double? protein; // g
  final double? fat; // g
  final double? carbs; // g
}

enum HealthStatus {
  unsupported, // 웹 · iOS 등 헬스 커넥트가 없는 플랫폼
  notInstalled, // 헬스 커넥트 미설치 또는 업데이트 필요
  notAuthorized, // 권한 아직 안 줌
  ready,
}
