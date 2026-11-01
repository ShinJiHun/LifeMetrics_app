import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import '../models/health_snapshot.dart';
import '../models/health_sync.dart';

// 안드로이드 헬스 커넥트에서 읽기 전용으로 데이터를 가져옴.
// 삼성헬스는 설정 > 헬스 커넥트 연동을 켜 두면 걸음 · 심박 · 수면 · 체성분 · 식사를 여기에 써줌
class HealthService {
  final Health _health = Health();
  bool _configured = false;

  // 화면에 보여주는 데이터
  static const displayTypes = [
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.HEART_RATE,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.WEIGHT,
    HealthDataType.BODY_FAT_PERCENTAGE,
    HealthDataType.NUTRITION,
  ];

  // 서버 동기화에만 쓰는 데이터 (운동 세션, 하루 이동 거리 · 총 소모 칼로리)
  static const syncOnlyTypes = [
    HealthDataType.WORKOUT,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.TOTAL_CALORIES_BURNED,
  ];

  // 권한은 한 번에 모두 요청
  static const types = [...displayTypes, ...syncOnlyTypes];
  static final _read = [for (final _ in types) HealthDataAccess.READ];

  // 삭제 감지(변경 토큰)를 걸어둘 레코드: 서버에 id 로 저장하는 식단 · 운동
  static const _changeTypes = [
    HealthDataType.NUTRITION,
    HealthDataType.WORKOUT,
  ];

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  Future<HealthStatus> status() async {
    if (!_supported) return HealthStatus.unsupported;
    await _configure();
    final sdk = await _health.getHealthConnectSdkStatus();
    if (sdk != HealthConnectSdkStatus.sdkAvailable) {
      return HealthStatus.notInstalled;
    }
    // 일부만 허용해도 읽을 수 있는 것만 보여주면 되므로 하나라도 있으면 통과
    for (final t in types) {
      if (await _health.hasPermissions(
            [t],
            permissions: [HealthDataAccess.READ],
          ) ==
          true) {
        return HealthStatus.ready;
      }
    }
    return HealthStatus.notAuthorized;
  }

  // 플레이 스토어의 헬스 커넥트 설치 화면으로 보냄
  Future<void> install() => _health.installHealthConnect();

  // 헬스 커넥트 권한 화면을 띄움. 사용자가 일부만 허용해도 true 가 아닐 수 있어
  // 결과는 status() 로 다시 확인
  Future<void> requestAuthorization() async {
    await _configure();
    await _health.requestAuthorization(types, permissions: _read);
  }

  // 오늘 포함 최근 [dayCount]일 요약
  Future<HealthSnapshot> fetch({int dayCount = 7, DateTime? now}) async {
    await _configure();
    final end = now ?? DateTime.now();
    final today = DateTime(end.year, end.month, end.day);
    final start = today.subtract(Duration(days: dayCount - 1));
    final days = [for (var i = 0; i < dayCount; i++) _addDays(start, i)];

    // 수면은 전날 저녁에 시작하므로 하루 앞에서부터, 체중은 측정이 드물어 30일
    final points = _health.removeDuplicates(
      await _health.getHealthDataFromTypes(
        types: displayTypes.where((t) => t != HealthDataType.STEPS).toList(),
        startTime: today.subtract(const Duration(days: 30)),
        endTime: end,
      ),
    );

    // 걸음은 폰과 워치가 겹쳐 기록하므로 헬스 커넥트의 합계(중복 제거)를 씀
    final steps = await Future.wait([
      for (final d in days)
        _health.getTotalStepsInInterval(d, d == today ? end : _addDays(d, 1)),
    ]);

    List<HealthDataPoint> of(
      HealthDataType t,
      DateTime day, {
      bool byEnd = false,
    }) => points.where((p) {
      if (p.type != t) return false;
      final at = byEnd ? p.dateTo : p.dateFrom;
      return !at.isBefore(day) && at.isBefore(_addDays(day, 1));
    }).toList();

    final daily = [
      for (final (i, d) in days.indexed)
        DailyHealth(
          day: d,
          steps: steps[i],
          activeKcal: _sum(of(HealthDataType.ACTIVE_ENERGY_BURNED, d)),
          sleepMinutes: _sum(of(HealthDataType.SLEEP_SESSION, d, byEnd: true))
              ?.round(),
          restingHr: _last(of(HealthDataType.RESTING_HEART_RATE, d))?.round(),
          avgHr: _avg(of(HealthDataType.HEART_RATE, d))?.round(),
        ),
    ];

    // 어제 먹은 음식. 삼성헬스는 음식 하나하나를 끼니 종류와 함께 따로 기록함
    final yesterday = _addDays(today, -1);
    final meals = [
      for (final p in of(HealthDataType.NUTRITION, yesterday))
        if (p.value case final NutritionHealthValue v)
          Meal(
            at: p.dateFrom,
            type: MealKind.fromHealth(v.mealType),
            name: v.name,
            calories: v.calories,
            protein: v.protein,
            fat: v.fat,
            carbs: v.carbs,
          ),
    ]..sort((a, b) => a.at.compareTo(b.at));

    final weight = _latest(points, HealthDataType.WEIGHT);
    final fat = _latest(points, HealthDataType.BODY_FAT_PERCENTAGE);

    return HealthSnapshot(
      days: daily,
      weight: weight == null ? null : _value(weight),
      weighedAt: weight?.dateFrom,
      bodyFat: fat == null ? null : _value(fat),
      yesterdayMeals: meals,
      // 다른 권한만 먼저 허용한 경우 식사 권한을 따로 요청할 수 있게
      mealsAuthorized:
          await _health.hasPermissions(
            [HealthDataType.NUTRITION],
            permissions: [HealthDataAccess.READ],
          ) ==
          true,
      sources: {for (final p in points) p.sourceName},
    );
  }

  // 동기화에 필요한 권한(식단 · 운동 · 거리 · 칼로리)이 모두 있는지.
  // 예전에 화면용 권한만 허용한 경우 동기화 전에 다시 요청해야 함
  Future<bool> hasSyncPermissions() async {
    await _configure();
    for (final t in [HealthDataType.NUTRITION, ...syncOnlyTypes]) {
      final ok = await _health.hasPermissions(
        [t],
        permissions: [HealthDataAccess.READ],
      );
      if (ok != true) return false;
    }
    return true;
  }

  // 이 기기의 헬스 커넥트가 백그라운드 읽기를 지원하는지
  Future<bool> supportsBackgroundRead() async {
    await _configure();
    return _health.isHealthDataInBackgroundAvailable();
  }

  Future<bool> hasBackgroundPermission() async {
    await _configure();
    return _health.isHealthDataInBackgroundAuthorized();
  }

  // 헬스 커넥트 권한 화면을 띄움. 결과는 hasBackgroundPermission() 으로 다시 확인
  Future<void> requestBackgroundPermission() async {
    await _configure();
    await _health.requestHealthDataInBackgroundAuthorization();
  }

  // 지금부터의 변경(삭제)을 추적할 토큰. 권한이 없으면 null
  Future<String?> newChangesToken() async {
    await _configure();
    try {
      return await _health.getChangesToken(types: _changeTypes);
    } catch (_) {
      return null;
    }
  }

  // [token] 이후 지워진 식단 · 운동 레코드 id 와 다음 토큰.
  // 토큰이 만료(헬스 커넥트는 약 30일)됐거나 읽지 못하면 null → 새 토큰부터 다시 시작
  Future<({List<String> ids, String nextToken})?> deletedSince(
    String token,
  ) async {
    await _configure();
    final ids = <String>[];
    var t = token;
    while (true) {
      final HealthChangesResponse? r;
      try {
        r = await _health.getChanges(changesToken: t);
      } catch (_) {
        return null;
      }
      if (r == null || r.changesTokenExpired) return null;
      ids.addAll(r.deletedRecordIds);
      t = r.nextChangesToken;
      if (!r.hasMore) break;
    }
    return (ids: ids, nextToken: t);
  }

  // 오늘 포함 최근 [dayCount]일을 서버로 보낼 모양으로 모음 (deletedIds 는 비어 있음)
  Future<HealthSyncPayload> collectForSync({
    int dayCount = 7,
    DateTime? now,
  }) async {
    await _configure();
    final end = now ?? DateTime.now();
    final today = DateTime(end.year, end.month, end.day);
    final start = today.subtract(Duration(days: dayCount - 1));
    final days = [for (var i = 0; i < dayCount; i++) _addDays(start, i)];

    // 수면은 전날 저녁에 시작하므로 하루 앞에서부터 읽음
    final points = _health.removeDuplicates(
      await _health.getHealthDataFromTypes(
        types: const [
          HealthDataType.SLEEP_SESSION,
          HealthDataType.RESTING_HEART_RATE,
          HealthDataType.NUTRITION,
          HealthDataType.WORKOUT,
        ],
        startTime: _addDays(start, -1),
        endTime: end,
      ),
    );

    // 걸음 · 거리 · 칼로리는 폰과 워치가 겹쳐 기록하므로 헬스 커넥트 합계(중복 제거)를 씀
    final steps = await Future.wait([
      for (final d in days)
        _health.getTotalStepsInInterval(d, d == today ? end : _addDays(d, 1)),
    ]);
    final totals = await _dailyTotals(start, end, const [
      HealthDataType.DISTANCE_DELTA,
      HealthDataType.ACTIVE_ENERGY_BURNED,
      HealthDataType.TOTAL_CALORIES_BURNED,
    ]);

    bool inDay(DateTime at, DateTime day) =>
        !at.isBefore(day) && at.isBefore(_addDays(day, 1));
    bool inWindow(DateTime at) => !at.isBefore(start) && !at.isAfter(end);

    final exercises = [
      for (final p in points)
        if (p.type == HealthDataType.WORKOUT &&
            p.uuid.isNotEmpty &&
            inWindow(p.dateFrom))
          if (p.value case final WorkoutHealthValue v)
            SyncExercise(
              id: p.uuid,
              type: v.workoutActivityType.name,
              startTime: p.dateFrom,
              endTime: p.dateTo,
              kcal: v.totalEnergyBurned?.toDouble(),
              distanceM: v.totalDistance?.toDouble(),
              sourceApp: p.sourceName,
            ),
    ];

    final nutrition = [
      for (final p in points)
        if (p.type == HealthDataType.NUTRITION &&
            p.uuid.isNotEmpty &&
            inWindow(p.dateFrom))
          if (p.value case final NutritionHealthValue v)
            nutritionFromHealth(p.uuid, p.dateFrom, v, p.sourceName),
    ];

    List<HealthDataPoint> of(
      HealthDataType t,
      DateTime day, {
      bool byEnd = false,
    }) => points
        .where((p) => p.type == t && inDay(byEnd ? p.dateTo : p.dateFrom, day))
        .toList();

    final daily = [
      for (final (i, d) in days.indexed)
        SyncDay(
          date: d,
          steps: steps[i],
          distanceM: totals[(HealthDataType.DISTANCE_DELTA, d)],
          activeKcal: totals[(HealthDataType.ACTIVE_ENERGY_BURNED, d)],
          totalKcal: totals[(HealthDataType.TOTAL_CALORIES_BURNED, d)],
          exerciseMinutes: _nullIfZero(
            exercises
                .where((e) => inDay(e.startTime, d))
                .fold<int>(0, (a, e) => a + e.minutes),
          ),
          sleepMinutes: _sum(of(HealthDataType.SLEEP_SESSION, d, byEnd: true))
              ?.round(),
          restingHeartRate: _last(of(HealthDataType.RESTING_HEART_RATE, d))
              ?.round(),
        ),
    ];

    return HealthSyncPayload(
      device: 'android',
      days: daily,
      nutrition: nutrition,
      exercises: exercises,
    );
  }

  // 하루 단위 헬스 커넥트 합계. 키는 (타입, 그날 00:00), 기록이 없는 날은 빠짐
  Future<Map<(HealthDataType, DateTime), double>> _dailyTotals(
    DateTime start,
    DateTime end,
    List<HealthDataType> types,
  ) async {
    final List<HealthDataPoint> points;
    try {
      points = await _health.getHealthIntervalDataFromTypes(
        startDate: start,
        endDate: end,
        types: types,
        interval: const Duration(days: 1).inSeconds,
      );
    } catch (_) {
      return const {};
    }
    return {
      for (final p in points)
        // 기록이 없는 구간도 0 으로 오므로 출처가 없으면 버림
        if (p.sourceName.isNotEmpty || _value(p) != 0)
          (p.type, DateTime(p.dateFrom.year, p.dateFrom.month, p.dateFrom.day)):
              _value(p),
    };
  }

  // 플러그인은 영양소를 모두 g 로 줌 → 서버 단위(mg, mcg)로 바꿈
  static SyncNutrition nutritionFromHealth(
    String id,
    DateTime at,
    NutritionHealthValue v,
    String? sourceApp,
  ) {
    double? mg(double? g) => g == null ? null : g * 1000;
    double? mcg(double? g) => g == null ? null : g * 1000000;
    return SyncNutrition(
      id: id,
      startTime: at,
      mealType: v.mealType,
      name: v.name,
      energyKcal: v.calories,
      carbsG: v.carbs,
      proteinG: v.protein,
      fatG: v.fat,
      saturatedFatG: v.fatSaturated,
      unsaturatedFatG: v.fatUnsaturated,
      polyunsaturatedFatG: v.fatPolyunsaturated,
      monounsaturatedFatG: v.fatMonounsaturated,
      transFatG: v.fatTransMonoenoic,
      cholesterolMg: mg(v.cholesterol),
      sodiumMg: mg(v.sodium),
      potassiumMg: mg(v.potassium),
      fiberG: v.fiber,
      sugarG: v.sugar,
      vitaminAMcg: mcg(v.vitaminA),
      vitaminCMg: mg(v.vitaminC),
      calciumMg: mg(v.calcium),
      ironMg: mg(v.iron),
      sourceApp: sourceApp,
    );
  }

  static int? _nullIfZero(int v) => v == 0 ? null : v;

  // 일광 절약 시간이 있어도 자정이 유지되도록 날짜 단위로 더함
  static DateTime _addDays(DateTime d, int n) =>
      DateTime(d.year, d.month, d.day + n);

  static double _value(HealthDataPoint p) =>
      (p.value as NumericHealthValue).numericValue.toDouble();

  static double? _sum(List<HealthDataPoint> ps) =>
      ps.isEmpty ? null : ps.map(_value).reduce((a, b) => a + b);

  static double? _avg(List<HealthDataPoint> ps) =>
      ps.isEmpty ? null : _sum(ps)! / ps.length;

  static HealthDataPoint? _newest(Iterable<HealthDataPoint> ps) => ps.isEmpty
      ? null
      : ps.reduce((a, b) => a.dateFrom.isAfter(b.dateFrom) ? a : b);

  static double? _last(List<HealthDataPoint> ps) {
    final p = _newest(ps);
    return p == null ? null : _value(p);
  }

  static HealthDataPoint? _latest(List<HealthDataPoint> ps, HealthDataType t) =>
      _newest(ps.where((p) => p.type == t));
}
