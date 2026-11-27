import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:workmanager/workmanager.dart';

import '../models/ride.dart';
import '../utils/format.dart';
import 'health_service.dart';
import 'ride_api.dart';

// 홈 화면 위젯 (안드로이드 LifeMetricsWidgetProvider): 오늘 걸음 · 이번 주 라이딩 · 최근 체중.
// 앱을 켤 때와 한 시간마다(WorkManager) 숫자를 모아 위젯 저장소에 넣고 위젯을 다시 그리게 함.
// 각 숫자는 따로 모아서, 하나가 실패해도 나머지는 갱신됨
class HomeWidgetService {
  HomeWidgetService._();

  // 위젯 클래스는 패키지(applicationId)가 아니라 코틀린 패키지 기준이라 전체 이름으로 지정
  // (개발 앱은 applicationId 가 .dev 로 끝나 짧은 이름으로는 못 찾음)
  static const providerClass =
      'com.example.lifemetrics_app.LifeMetricsWidgetProvider';
  static const taskName = 'lifemetrics.home_widget.refresh';
  static const _uniqueName = 'home-widget-refresh-hourly';

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  // 한 시간마다 갱신 예약. HealthAutoSync.initialize() 로 WorkManager 를 준비한 뒤에 부름
  static Future<void> schedule() async {
    if (!_supported) return;
    await Workmanager().registerPeriodicTask(
      _uniqueName,
      taskName,
      frequency: const Duration(hours: 1),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  static Future<void> refresh({
    HealthService? health,
    RideApi? rides,
    DateTime? now,
  }) async {
    if (!_supported) return;
    final t = now ?? DateTime.now();
    final h = health ?? HealthService();
    final values = <String, String>{
      'updated': '${t.hour.toString().padLeft(2, '0')}:'
          '${t.minute.toString().padLeft(2, '0')} 갱신',
    };
    try {
      final steps = await h.todaySteps(now: t);
      if (steps != null) values['steps'] = formatThousands(steps);
    } catch (e) {
      debugPrint('위젯: 걸음 못 읽음 $e');
    }
    try {
      final w = await h.latestWeight(now: t);
      if (w != null) values['weight'] = '${w.toStringAsFixed(1)} kg';
    } catch (e) {
      debugPrint('위젯: 체중 못 읽음 $e');
    }
    try {
      final list = await (rides ?? RideApi()).fetchRides(page: 0, size: 20);
      values['ride'] = '${weekRideKm(list, t).toStringAsFixed(1)} km';
    } catch (e) {
      debugPrint('위젯: 라이딩 못 읽음 $e');
    }
    try {
      for (final e in values.entries) {
        await HomeWidget.saveWidgetData<String>(e.key, e.value);
      }
      await HomeWidget.updateWidget(qualifiedAndroidName: providerClass);
    } catch (e) {
      debugPrint('위젯 갱신 실패: $e');
    }
  }

  // 이번 주(월요일 0시부터) 라이딩 거리 합 (km)
  static double weekRideKm(List<Ride> rides, DateTime now) {
    final monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    return rides
        .where((r) => !r.startTime.isBefore(monday))
        .fold(0.0, (sum, r) => sum + (r.distanceMeters ?? 0) / 1000);
  }
}
