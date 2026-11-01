import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'health_service.dart';
import 'health_sync_service.dart';

const _taskName = 'lifemetrics.health_sync.daily';

// WorkManager 가 앱과 별개의 엔진에서 깨우는 진입점
@pragma('vm:entry-point')
void healthAutoSyncDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  // 백그라운드 엔진에선 shared_preferences 같은 Dart 쪽 플러그인 등록을 직접 해야 함
  DartPluginRegistrant.ensureInitialized();
  Workmanager().executeTask((_, _) => runHealthAutoSync());
}

// true 면 이번 회차 끝, false 면 WorkManager 가 간격을 늘려가며 재시도
Future<bool> runHealthAutoSync({
  HealthService? health,
  HealthSyncService? sync,
}) async {
  final h = health ?? HealthService();
  final s = sync ?? HealthSyncService(health: h);
  try {
    // 권한 문제는 재시도해도 풀리지 않음. 사용자가 앱에서 다시 허용해야 함
    if (!s.configured ||
        !await h.hasBackgroundPermission() ||
        !await h.hasSyncPermissions()) {
      debugPrint('자동 동기화 건너뜀: 토큰 또는 권한 없음');
      return true;
    }
    final r = await s.sync();
    debugPrint(
      '자동 동기화 성공: 일 ${r.days} / 식단 ${r.nutrition} / '
      '운동 ${r.exercises} / 삭제 ${r.deleted}',
    );
    return true;
  } on HealthSyncRejected catch (e) {
    debugPrint('자동 동기화 거부됨: $e');
    return true;
  } catch (e) {
    debugPrint('자동 동기화 실패, 재시도 예정: $e');
    return false;
  }
}

// 하루 1회 자동 동기화 예약
class HealthAutoSync {
  const HealthAutoSync();

  static const _uniqueName = 'health-sync-daily';

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  // 앱 업데이트 뒤에도 콜백을 찾을 수 있도록 앱을 켤 때마다 등록
  static Future<void> initialize() async {
    if (_supported) await Workmanager().initialize(healthAutoSyncDispatcher);
  }

  Future<bool> isScheduled() async =>
      _supported && await Workmanager().isScheduledByUniqueName(_uniqueName);

  Future<void> enable() => Workmanager().registerPeriodicTask(
    _uniqueName,
    _taskName,
    frequency: const Duration(days: 1),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(minutes: 15),
  );

  Future<void> disable() => Workmanager().cancelByUniqueName(_uniqueName);
}
