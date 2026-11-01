import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import '../models/health_snapshot.dart';

// 안드로이드 헬스 커넥트에서 읽기 전용으로 데이터를 가져옴.
// 삼성헬스는 설정 > 헬스 커넥트 연동을 켜 두면 걸음 · 심박 · 수면 · 체성분 · 식사를 여기에 써줌
class HealthService {
  final Health _health = Health();
  bool _configured = false;

  static const types = [
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.HEART_RATE,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.WEIGHT,
    HealthDataType.BODY_FAT_PERCENTAGE,
    HealthDataType.NUTRITION,
  ];
  static final _read = [for (final _ in types) HealthDataAccess.READ];

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
        types: types.where((t) => t != HealthDataType.STEPS).toList(),
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
