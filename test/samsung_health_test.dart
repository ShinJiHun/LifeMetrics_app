import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lifemetrics_app/models/health_snapshot.dart';
import 'package:lifemetrics_app/screens/athlete/body/samsung_health_screen.dart';
import 'package:lifemetrics_app/services/health_service.dart';

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
}

void main() {
  Future<void> pump(WidgetTester tester, HealthService service) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: SamsungHealthScreen(service: service),
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
}
