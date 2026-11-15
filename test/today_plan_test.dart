import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lifemetrics_app/models/health_snapshot.dart';
import 'package:lifemetrics_app/models/today_plan.dart';
import 'package:lifemetrics_app/models/workout.dart';
import 'package:lifemetrics_app/screens/athlete/athlete_home_screen.dart';
import 'package:lifemetrics_app/models/athlete_section.dart';
import 'package:lifemetrics_app/screens/athlete/athlete_section_screen.dart';
import 'package:lifemetrics_app/screens/athlete/fitness/workout_input_entry.dart';
import 'package:lifemetrics_app/screens/athlete/fitness/workout_input_screen.dart';
import 'package:lifemetrics_app/screens/athlete/fitness/workout_recommend_screen.dart';
import 'package:lifemetrics_app/services/body_api.dart';
import 'package:lifemetrics_app/services/cut_planner.dart';
import 'package:lifemetrics_app/services/fitness_api.dart';
import 'package:lifemetrics_app/services/health_service.dart';
import 'package:lifemetrics_app/services/ride_api.dart';
import 'package:lifemetrics_app/services/workout_recommender.dart';

class _NoHealth extends HealthService {
  @override
  Future<HealthStatus> status() async => HealthStatus.unsupported;
}

const _treadmill = PlannedCardio(
  machine: CardioMachine.treadmill,
  name: '트레드밀 경사 걷기',
  gifUrl: '/api/exercise/gif/cardio/TREADMILL.gif',
  targetMinutes: 40,
  targetKcal: 400,
  intensity: 'Zone 2',
  how: '경사 10~12%',
  itemId: 872,
);

void main() {
  final today = DateTime(2026, 11, 15);
  final now = DateTime(2026, 11, 15, 19);

  test('유산소 실제 값 → 서버 기록 (기구 설정은 메모로), 시간 없으면 기록 안 함', () {
    expect(_treadmill.toLog(), isNull);
    final log = _treadmill.withActual({
      'minutes': '42',
      'kcal': '380',
      'incline': '12',
      'speed': '5.5',
      'avgHr': '128',
    }).toLog()!;
    expect(log.toLogJson(), {
      'exerciseItemId': 872,
      'durationMin': 42.0,
      'distanceKm': null,
      'kcal': 380,
      'avgHr': 128,
      'memo': '경사 12% · 속도 5.5km/h',
      'sets': const [],
    });
  });

  test('계획 JSON 저장 · 복원, 날짜가 지나면 불러오지 않음', () async {
    SharedPreferences.setMockInitialValues({});
    final plan = TodayPlan(
      date: today,
      goal: TrainingGoal.cut,
      exercises: const [
        Recommendation(
          item: ExerciseItem(id: 3, categoryId: 1, nameKo: '바벨 벤치 프레스'),
          part: BodyPart.chest,
          sets: 3,
          repsMin: 10,
          repsMax: 15,
          weight: 60,
          reason: '최근 기록 기준',
        ),
      ],
      cardio: _treadmill.withActual({'minutes': '30'}),
    );
    await TodayPlanStore.save(plan);
    final back = (await TodayPlanStore.load(now))!;
    expect(back.goal, TrainingGoal.cut);
    expect(back.exercises.single.weight, 60);
    expect(back.exercises.single.item.nameKo, '바벨 벤치 프레스');
    expect(back.cardio!.actual, {'minutes': '30'});
    expect(await TodayPlanStore.load(DateTime(2026, 11, 16)), isNull);
  });

  // 실제 서버 흉내: 종목 · 인바디 · 기록, POST 는 '저장 완료' 글자만
  (MockClient, List<Map<String, dynamic>>) server() {
    final posted = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      if (req.method == 'POST') {
        posted.add(
          jsonDecode(utf8.decode(req.bodyBytes)) as Map<String, dynamic>,
        );
        return http.Response.bytes(utf8.encode('저장 완료'), 200);
      }
      final body = switch (req.url.path) {
        '/api/exercise/items' => [
          {'id': 872, 'categoryId': 7, 'nameKo': '러닝머신'},
        ],
        '/api/exercise/history' || '/api/activity/list' => <Object>[],
        '/api/body/goals/current' => {
          'current': {'weight': 84.5, 'weightDate': '2026-10-21'},
        },
        '/api/body/weight-loss' => {'basalMetabolicRate': 1662.0},
        _ => throw StateError(req.url.path),
      };
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
    });
    return (client, posted);
  }

  void phone(WidgetTester tester, {double height = 2400}) {
    tester.view.physicalSize = Size(390, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('오늘 추천 저장: 유산소 고르면 저장 완료만 뜨고 화면은 그대로', (tester) async {
    SharedPreferences.setMockInitialValues({});
    phone(tester);
    final (client, posted) = server();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: WorkoutRecommendScreen(
          api: FitnessApi(client: client),
          bodyApi: BodyApi(client: client),
          rideApi: RideApi(client: client),
          health: _NoHealth(),
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('감량'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('유산소만 추천 받기'));
    await tester.pumpAndSettle();

    expect(find.text('이대로 입력하기'), findsNothing); // 웨이트가 없으니 저장만
    await tester.tap(find.text('오늘 추천 저장'));
    await tester.pumpAndSettle();
    expect(find.text('오늘 할 유산소를 골라 주세요'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('트레드밀 경사 걷기'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('오늘 추천을 저장했어요'), findsOneWidget);
    expect(find.byType(WorkoutRecommendScreen), findsOneWidget); // 넘어가지 않음
    expect(find.byType(WorkoutInputScreen), findsNothing);
    expect(find.text('저장한 오늘 운동이 있어요'), findsOneWidget);
    expect(posted, isEmpty); // 서버 기록은 아직

    final saved = (await TodayPlanStore.load(now))!;
    expect(saved.cardio!.name, '트레드밀 경사 걷기');
    expect(saved.cardio!.itemId, 872); // 서버 '러닝머신' 종목
    expect(saved.logged, isFalse);
  });

  testWidgets('입력 메뉴: 직접 입력 / 오늘 추천 운동 입력 고르기', (tester) async {
    SharedPreferences.setMockInitialValues({});
    phone(tester, height: 844);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: AthleteSectionScreen(section: AthleteSection.fitness),
      ),
    );
    await tester.tap(find.text('입력'));
    await tester.pumpAndSettle();
    expect(find.text('어떻게 입력할까요?'), findsOneWidget);
    expect(find.textContaining('저장한 오늘 추천이 없어요'), findsOneWidget);

    // 저장한 추천이 없으면 추천 쪽은 눌러도 그대로
    await tester.tap(find.text('오늘 추천 운동 입력'));
    await tester.pumpAndSettle();
    expect(find.text('어떻게 입력할까요?'), findsOneWidget);

    await tester.tap(find.text('직접 입력'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutInputScreen), findsOneWidget);
    expect(find.text('운동 입력'), findsOneWidget);
  });

  testWidgets('오늘 추천 운동 입력: 추천 목록 + 유산소 실제 값 → 저장하면 서버 기록', (tester) async {
    SharedPreferences.setMockInitialValues({
      'today_plan': jsonEncode(
        TodayPlan(
          date: today,
          goal: TrainingGoal.cut,
          exercises: const [
            Recommendation(
              item: ExerciseItem(id: 3, categoryId: 1, nameKo: '바벨 벤치 프레스'),
              part: BodyPart.chest,
              sets: 3,
              repsMin: 10,
              repsMax: 15,
              weight: 60,
              reason: '최근 기록 기준',
            ),
          ],
          cardio: _treadmill,
        ).toJson(),
      ),
    });
    phone(tester);
    final (client, posted) = server();
    final api = FitnessApi(client: client);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openWorkoutInput(context, api: api, now: now),
              child: const Text('입력 열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('입력 열기'));
    await tester.pumpAndSettle();
    expect(find.text('웨이트 1개 · 트레드밀 경사 걷기 40분'), findsOneWidget);
    await tester.tap(find.text('오늘 추천 운동 입력'));
    await tester.pumpAndSettle();

    // 추천 목록(무게 · 횟수 미리 채움)과 고른 유산소 입력칸
    expect(find.text('오늘 추천 운동 입력'), findsOneWidget);
    expect(find.text('바벨 벤치 프레스'), findsOneWidget);
    expect(find.text('60'), findsNWidgets(3));
    expect(find.text('유산소 · 트레드밀 경사 걷기'), findsOneWidget);

    Finder input(String label) => find.widgetWithText(TextField, label);
    await tester.enterText(input('실제 시간'), '42');
    await tester.enterText(input('기기 칼로리'), '380');
    await tester.enterText(input('경사'), '12');
    await tester.enterText(input('속도'), '5.5');
    await tester.pump();
    expect((await TodayPlanStore.load(now))!.cardio!.actual['kcal'], '380');

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    final entries = (posted.single['exercises'] as List).cast<Map>();
    expect(posted.single['sessionDate'], '2026-11-15');
    expect(entries.first['exerciseItemId'], 3);
    expect((entries.first['sets'] as List).length, 3);
    final cardio = entries.last;
    expect(cardio['exerciseItemId'], 872);
    expect(cardio['durationMin'], 42.0);
    expect(cardio['kcal'], 380);
    expect(cardio['memo'], '경사 12% · 속도 5.5km/h');

    expect(find.byType(WorkoutInputScreen), findsNothing); // 저장하면 닫힘
    expect(find.text('운동을 저장했어요'), findsOneWidget);
    expect((await TodayPlanStore.load(now))!.logged, isTrue);
  });

  testWidgets('앱을 열면 기록 전인 오늘 추천 입력 화면이 바로 뜸', (tester) async {
    SharedPreferences.setMockInitialValues({
      'today_plan': jsonEncode(
        TodayPlan(
          date: today,
          goal: TrainingGoal.cut,
          exercises: const [],
          cardio: _treadmill,
        ).toJson(),
      ),
    });
    AthleteHomeScreen.resetAutoOpen();
    phone(tester, height: 844);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(body: AthleteHomeScreen(now: now)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutInputScreen), findsOneWidget);
    expect(find.text('오늘 추천 운동 입력'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('오늘의 운동'), findsOneWidget);
    expect(find.text('트레드밀 경사 걷기 40분'), findsOneWidget);
  });

  testWidgets('하단 저장 버튼은 제스처 바 위로 24 더 띄움', (tester) async {
    SharedPreferences.setMockInitialValues({});
    phone(tester, height: 844);
    tester.view.padding = const FakeViewPadding(bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: WorkoutInputScreen(
          now: now,
          plan: TodayPlan(
            date: today,
            goal: TrainingGoal.cut,
            exercises: const [],
            cardio: _treadmill,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = tester.getRect(find.byType(FilledButton));
    expect(button.bottom, 844 - 48 - 24);
  });
}
