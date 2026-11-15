import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lifemetrics_app/models/health_snapshot.dart';
import 'package:lifemetrics_app/screens/athlete/fitness/workout_recommend_screen.dart';
import 'package:lifemetrics_app/services/body_api.dart';
import 'package:lifemetrics_app/services/cut_planner.dart';
import 'package:lifemetrics_app/services/fitness_api.dart';
import 'package:lifemetrics_app/services/health_service.dart';
import 'package:lifemetrics_app/services/ride_api.dart';

class _FakeHealth extends HealthService {
  _FakeHealth(this.snapshot);

  final HealthSnapshot snapshot;

  @override
  Future<HealthStatus> status() async => HealthStatus.ready;

  @override
  Future<HealthSnapshot> fetch({int dayCount = 7, DateTime? now}) async =>
      snapshot;
}

void main() {
  group('CutPlanner', () {
    test('인바디 목표까지 남은 감량을 달 수로 나눠 0.5kg 단위, 상한은 주 1%', () {
      expect(
        CutPlanner.suggestMonthlyLoss(
          weightKg: 84.5,
          targetWeight: 70.4,
          targetDate: DateTime(2027, 7, 4),
          today: DateTime(2026, 11, 15),
        ),
        2.0,
      );
      expect(CutPlanner.maxMonthlyLoss(84.5), 3.5);
      // 목표가 없으면 체중의 2%
      expect(
        CutPlanner.suggestMonthlyLoss(
          weightKg: 84.5,
          today: DateTime(2026, 11, 15),
        ),
        1.5,
      );
    });

    test('남은 적자를 유산소 시간으로, 따릉이를 오래 탔으면 사이클 추천 + FTP 와트', () {
      final plan = CutPlanner.plan(
        const EnergyInputs(
          weightKg: 84.5,
          bmr: 1662,
          monthlyLossKg: 2,
          intakeKcal: 2600,
          mealCount: 3,
          steps: 8000,
          activeKcal: 400,
          bikeKcal: 136,
          bikeMinutes: 56,
          bikeRides: 1,
          strengthMinutes: 40,
          ftp: 210,
        ),
      );
      expect(plan.targetDeficit.round(), 513);
      expect(plan.burned.round(), 2754);
      expect(plan.remaining.round(), 360);
      final primary = plan.options.singleWhere((o) => o.primary);
      expect(primary.name, '실내 사이클');
      expect(primary.minutes, 40);
      expect(primary.how, contains('118~158W'));
      expect(plan.options.length, 3); // 400kcal 이하라 인터벌 없음
      expect(plan.foodCut, 0);
    });

    test('이미 목표 적자를 채웠으면 회복용 걷기만', () {
      final plan = CutPlanner.plan(
        const EnergyInputs(
          weightKg: 84.5,
          bmr: 1662,
          monthlyLossKg: 2,
          intakeKcal: 1500,
          mealCount: 2,
          activeKcal: 600,
        ),
      );
      expect(plan.remaining, lessThan(0));
      expect(plan.options.single.intensity, '회복');
    });

    test('식사 기록이 없으면 목표 적자의 절반, 걸음이 적으면 걷기 추천', () {
      final plan = CutPlanner.plan(
        const EnergyInputs(
          weightKg: 84.5,
          bmr: 1662,
          monthlyLossKg: 2,
          steps: 3000,
        ),
      );
      expect(plan.intake, isNull);
      expect(plan.remaining.round(), 257);
      expect(plan.activeFromSteps, isTrue);
      expect(plan.options.singleWhere((o) => o.primary).name, '트레드밀 경사 걷기');
      expect(plan.notes.join(), contains('3000보'));
    });

    test('많이 남으면 60분 상한, 나머지는 식사로', () {
      final plan = CutPlanner.plan(
        const EnergyInputs(
          weightKg: 84.5,
          bmr: 1662,
          monthlyLossKg: 3.5,
          intakeKcal: 3200,
          mealCount: 4,
          activeKcal: 200,
        ),
      );
      final primary = plan.options.singleWhere((o) => o.primary);
      expect(primary.name, '스텝밀');
      expect(primary.minutes, 60);
      expect(plan.foodCut, greaterThan(0));
      expect(plan.options.any((o) => o.intensity == '인터벌'), isTrue);
    });
  });

  testWidgets('화면: 감량 → 인바디 목표 → 따릉이 · 삼성헬스 반영한 유산소', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final client = MockClient((req) async {
      final body = switch (req.url.path) {
        '/api/exercise/items' => <Object>[],
        '/api/exercise/history' => <Object>[],
        '/api/body/goals/current' => {
          'goal': {'targetWeight': 70.4, 'targetDate': '2027-07-04'},
          'current': {'weight': 84.5, 'weightDate': '2026-10-21'},
          'ftp': 210,
        },
        '/api/body/weight-loss' => {
          'weight': 84.5,
          'recordDate': '2026-10-21',
          'basalMetabolicRate': 1662.0,
        },
        '/api/activity/list' => [
          {
            'id': 1,
            'startTime': '2026-11-15T07:52:00Z',
            'rideType': 'DDAREUNGI',
            'movingTime': 3360,
            'calories': 136,
          },
          {
            'id': 2,
            'startTime': '2026-11-14T07:52:00Z',
            'rideType': 'DDAREUNGI',
            'movingTime': 3360,
            'calories': 999, // 어제라 빠져야 함
          },
        ],
        _ => throw StateError(req.url.path),
      };
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
    });

    final now = DateTime(2026, 11, 15, 19);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: WorkoutRecommendScreen(
          api: FitnessApi(client: client),
          bodyApi: BodyApi(client: client),
          rideApi: RideApi(client: client),
          health: _FakeHealth(
            HealthSnapshot(
              days: [
                DailyHealth(
                  day: DateTime(2026, 11, 15),
                  steps: 8000,
                  activeKcal: 400,
                ),
              ],
              todayMeals: [
                Meal(
                  at: DateTime(2026, 11, 15, 8),
                  type: MealKind.breakfast,
                  calories: 700,
                ),
                Meal(
                  at: DateTime(2026, 11, 15, 12),
                  type: MealKind.lunch,
                  calories: 900,
                ),
                Meal(
                  at: DateTime(2026, 11, 15, 18),
                  type: MealKind.dinner,
                  calories: 1000,
                ),
              ],
            ),
          ),
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('감량'));
    await tester.pumpAndSettle();
    expect(find.text('2kg'), findsOneWidget);
    expect(find.textContaining('권장 2kg'), findsOneWidget);

    await tester.tap(find.text('유산소만 추천 받기'));
    await tester.pumpAndSettle();

    expect(find.text('오늘 칼로리 분석'), findsOneWidget);
    expect(find.text('2,600kcal'), findsOneWidget); // 먹은 것
    expect(find.text('136kcal'), findsOneWidget); // 오늘 따릉이만
    expect(find.text('1회 · 56분'), findsOneWidget);
    expect(find.text('오늘 추천'), findsOneWidget);
    expect(find.textContaining('118~158W'), findsOneWidget);
  });
}
