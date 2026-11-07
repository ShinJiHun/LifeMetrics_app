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

// 다음 한국 시각 00:00 까지 남은 시간. 서버 일일 분석(01:30 KST, 전날 분)보다 먼저 하루치가 올라가게 한다.
Duration delayUntilNextKstMidnight(DateTime now) {
  final kst = now.toUtc().add(const Duration(hours: 9));
  final nextMidnightKst = DateTime.utc(kst.year, kst.month, kst.day + 1);
  return nextMidnightKst.difference(kst);
}

// 하루 1회 자동 동기화 예약 (한국 시각 00시 무렵. 안드로이드가 절전 상태면 조금 늦게 돌 수 있음)
class HealthAutoSync {
  const HealthAutoSync();

  static const _uniqueName = 'health-sync-daily-kst0';
  // 예전 이름: 켠 시각 기준으로 하루마다 돌던 작업. 앱을 켤 때 00시 작업으로 갈아 끼운다
  static const _legacyUniqueName = 'health-sync-daily';

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  // 앱 업데이트 뒤에도 콜백을 찾을 수 있도록 앱을 켤 때마다 등록
  static Future<void> initialize() async {
    if (!_supported) return;
    await Workmanager().initialize(healthAutoSyncDispatcher);
    if (await Workmanager().isScheduledByUniqueName(_legacyUniqueName)) {
      await Workmanager().cancelByUniqueName(_legacyUniqueName);
      await const HealthAutoSync().enable();
    }
  }

  Future<bool> isScheduled() async =>
      _supported && await Workmanager().isScheduledByUniqueName(_uniqueName);

  Future<void> enable() => Workmanager().registerPeriodicTask(
    _uniqueName,
    _taskName,
    frequency: const Duration(days: 1),
    initialDelay: delayUntilNextKstMidnight(DateTime.now()),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(minutes: 15),
  );

  Future<void> disable() => Workmanager().cancelByUniqueName(_uniqueName);
}
