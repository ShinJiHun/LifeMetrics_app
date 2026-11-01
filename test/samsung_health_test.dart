import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lifemetrics_app/models/health_snapshot.dart';
import 'package:lifemetrics_app/screens/athlete/body/samsung_health_screen.dart';
import 'package:lifemetrics_app/models/health_sync.dart';
import 'package:lifemetrics_app/services/health_auto_sync.dart';
import 'package:lifemetrics_app/services/health_service.dart';
import 'package:lifemetrics_app/services/health_sync_service.dart';

// 헬스 커넥트 대신 정해진 상태와 데이터를 돌려줌
class _FakeHealth extends HealthService {
  _FakeHealth(this._status, [this._snapshot]);

  HealthStatus _status;
  final HealthSnapshot? _snapshot;
  int authRequests = 0;

  @override
  Future<HealthStatus> status() async => _status;

  @override
  Future<void> requestAuthorization() async {
    authRequests++;
    _status = HealthStatus.ready;
  }

  @override
  Future<HealthSnapshot> fetch({int dayCount = 7, DateTime? now}) async =>
      _snapshot!;

  bool syncPermitted = true;

  @override
  Future<bool> hasSyncPermissions() async => syncPermitted;

  bool backgroundSupported = true;
  bool backgroundPermitted = false;
  bool grantBackgroundOnRequest = true;

  @override
  Future<bool> supportsBackgroundRead() async => backgroundSupported;

  @override
  Future<bool> hasBackgroundPermission() async => backgroundPermitted;

  @override
  Future<void> requestBackgroundPermission() async {
    backgroundPermitted = grantBackgroundOnRequest;
  }
}

// WorkManager 대신 예약 여부만 기억함
class _FakeAuto extends HealthAutoSync {
  bool scheduled = false;

  @override
  Future<bool> isScheduled() async => scheduled;

  @override
  Future<void> enable() async => scheduled = true;

  @override
  Future<void> disable() async => scheduled = false;
}

// 서버 대신 정해진 결과를 돌려줌
class _FakeSync extends HealthSyncService {
  _FakeSync(HealthService health) : super(health: health, token: 't');

  int calls = 0;
  DateTime? last;

  @override
  Future<DateTime?> lastSyncedAt() async => last;

  @override
  Future<HealthSyncResult> sync({DateTime? now}) async {
    calls++;
    last = DateTime(2026, 11, 1, 21, 5);
    return const HealthSyncResult(
      days: 7,
      nutrition: 3,
      exercises: 1,
      deleted: 0,
    );
  }
}

void main() {
  // 화면이 마지막 동기화 시각을 기기 저장소에서 읽음
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(
    WidgetTester tester,
    HealthService service, {
    HealthSyncService? sync,
    HealthAutoSync? auto,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: SamsungHealthScreen(
          service: service,
          syncService: sync,
          autoSync: auto ?? _FakeAuto(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final snapshot = HealthSnapshot(
    days: [
      for (var i = 0; i < 6; i++)
        DailyHealth(day: DateTime(2026, 10, 26 + i), steps: 5000 + i * 100),
      DailyHealth(
        day: DateTime(2026, 11, 1),
        steps: 12345,
        activeKcal: 432,
        sleepMinutes: 412,
        restingHr: 52,
      ),
    ],
    weight: 71.3,
    bodyFat: 14.2,
    weighedAt: DateTime(2026, 10, 30),
    yesterdayMeals: [
      Meal(
        at: DateTime(2026, 10, 31, 8),
        type: MealKind.breakfast,
        name: '오트밀',
        calories: 300,
        carbs: 50,
        protein: 10,
      ),
      Meal(
        at: DateTime(2026, 10, 31, 12),
        type: MealKind.lunch,
        name: '제육볶음',
        calories: 650,
        carbs: 70,
        protein: 35,
      ),
      Meal(
        at: DateTime(2026, 10, 31, 12, 5),
        type: MealKind.lunch,
        name: '공기밥',
        calories: 300,
        carbs: 65,
        protein: 5,
      ),
    ],
    sources: {'com.sec.android.app.shealth'},
  );

  testWidgets('웹 · iOS 에서는 안내만 보여줌', (tester) async {
    await pump(tester, _FakeHealth(HealthStatus.unsupported));
    expect(find.text('안드로이드 폰에서만 볼 수 있어요'), findsOneWidget);
  });

  testWidgets('권한 허용 후 오늘 수치와 체성분을 보여줌', (tester) async {
    final service = _FakeHealth(HealthStatus.notAuthorized, snapshot);
    await pump(tester, service);

    await tester.tap(find.text('권한 허용'));
    await tester.pumpAndSettle();

    expect(service.authRequests, 1);
    expect(find.text('12,345 걸음', findRichText: true), findsOneWidget);
    expect(find.text('432 kcal', findRichText: true), findsOneWidget);
    expect(find.text('6시간 52분', findRichText: true), findsOneWidget);
    expect(find.text('52 bpm', findRichText: true), findsOneWidget);
    expect(find.text('안정시 심박'), findsOneWidget);
    expect(find.text('71.3 kg', findRichText: true), findsOneWidget);
    expect(find.text('최근 체성분 · 2026.10.30'), findsOneWidget);

    // 어제 식사: 총합 · 탄단지 · 끼니별 소계
    await tester.scrollUntilVisible(
      find.text('제육볶음'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('1,250 kcal', findRichText: true), findsOneWidget);
    expect(find.text('탄수화물 185g · 단백질 50g'), findsOneWidget);
    expect(find.text('아침'), findsOneWidget);
    expect(find.text('950 kcal'), findsOneWidget);
    expect(find.text('공기밥'), findsOneWidget);
    expect(find.text('저녁'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('식사 권한만 없으면 식사 카드에 권한 버튼', (tester) async {
    final service = _FakeHealth(
      HealthStatus.ready,
      HealthSnapshot(
        days: [DailyHealth(day: DateTime(2026, 11, 1), steps: 100)],
        mealsAuthorized: false,
      ),
    );
    await pump(tester, service);

    expect(find.text('식사 기록 권한이 필요해요'), findsOneWidget);
    await tester.tap(find.text('권한 허용'));
    await tester.pumpAndSettle();
    expect(service.authRequests, 1);
  });

  testWidgets('지금 올리기 → 서버 반영 건수와 마지막 시각', (tester) async {
    final health = _FakeHealth(
      HealthStatus.ready,
      HealthSnapshot(
        days: [DailyHealth(day: DateTime(2026, 11, 1), steps: 100)],
      ),
    );
    final sync = _FakeSync(health);
    await pump(tester, health, sync: sync);

    expect(find.text('아직 서버에 올린 적 없어요'), findsOneWidget);
    await tester.tap(find.text('지금 올리기'));
    await tester.pumpAndSettle();

    expect(sync.calls, 1);
    expect(find.text('서버에 올렸어요 · 7일, 식사 3건, 운동 1건'), findsOneWidget);
    expect(find.text('마지막 2026년 11월 1일 오후 9:05'), findsOneWidget);
  });

  testWidgets('동기화 권한을 끝내 안 주면 올리지 않음', (tester) async {
    final health = _FakeHealth(
      HealthStatus.ready,
      HealthSnapshot(
        days: [DailyHealth(day: DateTime(2026, 11, 1), steps: 100)],
      ),
    )..syncPermitted = false;
    final sync = _FakeSync(health);
    await pump(tester, health, sync: sync);

    await tester.tap(find.text('지금 올리기'));
    await tester.pumpAndSettle();

    expect(health.authRequests, 1);
    expect(sync.calls, 0);
    expect(find.textContaining('권한을 허용해야'), findsOneWidget);
  });

  testWidgets('토큰 없이 빌드하면 버튼이 꺼져 있음', (tester) async {
    final health = _FakeHealth(
      HealthStatus.ready,
      HealthSnapshot(
        days: [DailyHealth(day: DateTime(2026, 11, 1), steps: 100)],
      ),
    );
    await pump(
      tester,
      health,
      sync: HealthSyncService(health: health, token: ''),
    );

    expect(find.text('앱에 동기화 토큰이 없어 올릴 수 없어요'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '지금 올리기'),
    );
    expect(button.onPressed, isNull);
  });

  group('자동 동기화 스위치', () {
    Switch sw(WidgetTester t) => t.widget<Switch>(find.byType(Switch));

    testWidgets('켜면 백그라운드 권한을 받고 예약, 끄면 취소', (tester) async {
      final health = _FakeHealth(HealthStatus.ready, snapshot);
      final auto = _FakeAuto();
      await pump(tester, health, sync: _FakeSync(health), auto: auto);
      expect(sw(tester).value, isFalse);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(health.backgroundPermitted, isTrue);
      expect(auto.scheduled, isTrue);
      expect(sw(tester).value, isTrue);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(auto.scheduled, isFalse);
      expect(sw(tester).value, isFalse);
    });

    testWidgets('백그라운드 권한을 거절하면 예약하지 않음', (tester) async {
      final health = _FakeHealth(HealthStatus.ready, snapshot)
        ..grantBackgroundOnRequest = false;
      final auto = _FakeAuto();
      await pump(tester, health, sync: _FakeSync(health), auto: auto);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(auto.scheduled, isFalse);
      expect(sw(tester).value, isFalse);
      expect(find.text('백그라운드 읽기 권한을 허용해야 켤 수 있어요'), findsOneWidget);
    });

    testWidgets('지원하지 않는 기기면 예약하지 않음', (tester) async {
      final health = _FakeHealth(HealthStatus.ready, snapshot)
        ..backgroundSupported = false;
      final auto = _FakeAuto();
      await pump(tester, health, sync: _FakeSync(health), auto: auto);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(auto.scheduled, isFalse);
    });

    testWidgets('예약돼 있어도 권한이 회수됐으면 꺼진 것으로 보여줌', (tester) async {
      final health = _FakeHealth(HealthStatus.ready, snapshot);
      await pump(
        tester,
        health,
        sync: _FakeSync(health),
        auto: _FakeAuto()..scheduled = true,
      );

      expect(sw(tester).value, isFalse);
    });
  });
}
