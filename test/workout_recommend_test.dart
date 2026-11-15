import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lifemetrics_app/models/workout.dart';
import 'package:lifemetrics_app/screens/athlete/fitness/workout_input_screen.dart';
import 'package:lifemetrics_app/screens/athlete/fitness/workout_recommend_screen.dart';
import 'package:lifemetrics_app/services/fitness_api.dart';
import 'package:lifemetrics_app/services/workout_recommender.dart';

ExerciseItem item(
  int id,
  int cat,
  String name, {
  String equip = 'FREE_WEIGHT',
  String? gif = 'auto',
}) => ExerciseItem(
  id: id,
  categoryId: cat,
  nameKo: name,
  equipmentType: equip,
  gifUrl: gif == 'auto' ? '/api/exercise/gif/x/$id.gif' : gif,
);

WorkoutSession session(
  int id,
  DateTime date,
  int itemId,
  List<(double, int)> sets,
) => WorkoutSession(
  id: id,
  date: date,
  isPT: false,
  exercises: [
    WorkoutExercise(
      exerciseItemId: itemId,
      sets: [
        for (final (i, (w, r)) in sets.indexed)
          WorkoutSet(setNumber: i + 1, weight: w, reps: r),
      ],
    ),
  ],
);

void main() {
  group('summarize', () {
    test('가장 최근 세션의 가장 무거운 세트와 횟수', () {
      final r = WorkoutRecommender.summarize([
        session(1, DateTime(2026, 11, 1), 3, [(40, 12)]),
        session(2, DateTime(2026, 11, 10), 3, [(50, 10), (60, 6), (60, 8)]),
      ]);
      expect(r[3]!.topWeight, 60);
      expect(r[3]!.topReps, 8);
      expect(r[3]!.times, 2);
      expect(r[3]!.lastDate, DateTime(2026, 11, 10));
    });
  });

  group('recommend', () {
    final items = [
      item(1, 1, '푸쉬업', equip: 'BODYWEIGHT'),
      item(2, 1, '체스트 프레스 머신', equip: 'MACHINE'),
      item(3, 1, '바벨 벤치 프레스'),
      item(4, 1, '덤벨 플라이'),
      item(5, 1, 'GIF 없는 운동', gif: null),
      item(6, 1, '같은 GIF 중복', gif: '/api/exercise/gif/x/3.gif'),
      item(7, 9, '케이블 푸시다운', equip: 'CABLE'),
      item(8, 7, '트레드밀', equip: 'MACHINE'),
    ];

    test('GIF 있는 종목만, 같은 GIF 는 하나만, 프리웨이트 먼저', () {
      final recs = WorkoutRecommender.recommend(
        parts: [BodyPart.chest],
        goal: TrainingGoal.hypertrophy,
        items: items,
      );
      final ids = recs.map((r) => r.item.id).toList();
      expect(ids, isNot(contains(5)));
      expect(ids.where((id) => id == 3 || id == 6).length, 1);
      expect(recs.first.item.equipmentType, 'FREE_WEIGHT');
      expect(recs.last.item.equipmentType, 'BODYWEIGHT');
    });

    test('해 본 운동은 기록 기준 무게, 처음이면 무게 없음', () {
      final records = WorkoutRecommender.summarize([
        session(1, DateTime(2026, 11, 10), 3, [(60, 12)]),
      ]);
      final recs = WorkoutRecommender.recommend(
        parts: [BodyPart.chest],
        goal: TrainingGoal.hypertrophy,
        items: items,
        records: records,
      );
      final bench = recs.firstWhere((r) => r.item.id == 3);
      // 60 × 12 → 1RM 84 → 10회 63 → 2.5 단위 내림 62.5
      expect(bench.weight, 62.5);
      expect(bench.reason, contains('증량'));
      expect(recs.firstWhere((r) => r.item.id == 4).weight, isNull);
      expect(planText(bench), '62.5kg × 10회 × 4세트');
    });

    test('팔은 삼두 카테고리 포함, 유산소는 시간', () {
      final recs = WorkoutRecommender.recommend(
        parts: [BodyPart.arms, BodyPart.cardio],
        goal: TrainingGoal.strength,
        items: items,
      );
      expect(recs.map((r) => r.item.id), containsAll([7, 8]));
      final cardio = recs.firstWhere((r) => r.item.id == 8);
      expect(cardio.minutes, TrainingGoal.strength.cardioMin);
      expect(planText(cardio), '15분');
    });

    test('targetWeight 는 단위로 내림, 최소 1단위', () {
      expect(WorkoutRecommender.targetWeight(20, 10, 5, 2), 22);
      expect(WorkoutRecommender.targetWeight(1, 5, 20, 2.5), 2.5);
    });
  });

  testWidgets('화면: 부위 고르기 → 추천 → 이대로 입력하기', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final client = MockClient((req) async {
      final body = switch (req.url.path) {
        '/api/exercise/items' => [
          {
            'id': 3,
            'categoryId': 1,
            'nameKo': '바벨 벤치 프레스',
            'equipmentType': 'FREE_WEIGHT',
            'gifUrl': '/api/exercise/gif/chest/BENCH_PRESS.gif',
          },
        ],
        '/api/exercise/history'
            when req.url.queryParameters['month'] == '2026-11' =>
          [
            {
              'id': 9,
              'sessionDate': '2026-11-10',
              'logs': [
                {
                  'exerciseItemId': 3,
                  'sets': [
                    {'setNumber': 1, 'weight': 60.0, 'reps': 12},
                  ],
                },
              ],
            },
          ],
        _ => [],
      };
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: WorkoutRecommendScreen(
          api: FitnessApi(client: client),
          now: DateTime(2026, 11, 15),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('부위를 골라 주세요'), findsOneWidget);
    await tester.tap(find.text('가슴'));
    await tester.pump();
    await tester.tap(find.text('추천 받기'));
    await tester.pump();

    expect(find.text('1. 바벨 벤치 프레스'), findsOneWidget);
    expect(find.text('62.5kg × 10회 × 4세트'), findsOneWidget);

    await tester.tap(find.text('이대로 운동 입력하기'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutInputScreen), findsOneWidget);
    expect(find.text('4세트'), findsOneWidget);
    expect(find.text('62.5'), findsNWidgets(4));
  });
}
