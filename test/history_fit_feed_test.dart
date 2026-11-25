import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lifemetrics_app/models/bike.dart';
import 'package:lifemetrics_app/models/workout.dart';
import 'package:lifemetrics_app/screens/athlete/gear/bike_fit_form_screen.dart';
import 'package:lifemetrics_app/services/bike_api.dart';
import 'package:lifemetrics_app/services/dev_import_service.dart';
import 'package:lifemetrics_app/services/ride_api.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('운동 기록: 유산소는 시간 · 거리 · 칼로리 · 심박, 시트 표식은 메모에서 뺌', () {
    final cardio = WorkoutExercise.fromJson({
      'exerciseItemId': 872,
      'exerciseNameKo': '러닝머신',
      'categoryName': '유산소',
      'cardio': true,
      'durationSec': 1800,
      'distanceKm': 2.5,
      'kcal': 250,
      'avgHr': 140,
      'memo': '[cardio#12] 경사 12% · 속도 5.5km/h',
      'sets': [],
    });
    expect(cardio.isCardio, isTrue);
    expect(cardio.cardioSummary, '30분 · 2.5km · 250kcal · 평균 심박 140');
    expect(cardio.brief, '30분');
    expect(cardio.memo, '경사 12% · 속도 5.5km/h');

    final weight = WorkoutExercise.fromJson({
      'exerciseItemId': 31,
      'exerciseNameKo': '덤벨 벤치 프레스',
      'categoryName': '가슴',
      'cardio': false,
      'sets': [
        {'setNumber': 1, 'weight': 12.5, 'reps': 15},
        {'setNumber': 2, 'weight': 14.0, 'reps': 12},
      ],
    });
    expect(weight.isCardio, isFalse);
    expect(weight.brief, '2세트');
    expect(formatClockShort(1830), '30분 30초');
  });

  test('라이딩 목록: 피드는 page · size 로, 나머지는 서버 기본', () async {
    final queries = <Map<String, String>>[];
    final api = RideApi(
      client: MockClient((req) async {
        queries.add(req.url.queryParameters);
        return _json([]);
      }),
    );
    await api.fetchRides(page: 2, size: 10);
    await api.fetchRides();
    expect(queries[0], {'page': '2', 'size': '10', 'userId': '1'});
    expect(queries[1], {'userId': '1'});
  });

  test('개발 서버 기록 옮기기: 운영에 없는 것만 찾아 운영 저장 API 로 다시 보냄', () async {
    Map<String, Object?> session(int id, String date, List<Map<String, Object?>> logs) => {
      'id': id,
      'sessionDate': date,
      'isPT': false,
      'logs': logs,
    };
    final bench = {
      'exerciseItemId': 31,
      'exerciseNameKo': '덤벨 벤치 프레스',
      'cardio': false,
      'sets': [
        {'setNumber': 1, 'weight': 12.5, 'reps': 15},
      ],
    };
    final treadmill = {
      'exerciseItemId': 872,
      'exerciseNameKo': '러닝머신',
      'cardio': true,
      'durationSec': 1800,
      'kcal': 250,
      'memo': '경사 12% · 속도 5.5km/h',
      'sets': [],
    };
    Map<String, dynamic>? posted;
    final service = DevImportService(
      devBase: 'http://dev.test:8081',
      client: MockClient((req) async {
        if (req.method == 'POST') {
          expect(req.url.path, '/api/exercise/log');
          expect(req.url.host, isNot('dev.test'));
          posted = jsonDecode(req.body) as Map<String, dynamic>;
          return _json('저장 완료');
        }
        final isDev = req.url.host == 'dev.test';
        final month = req.url.queryParameters['month'];
        if (month != '2026-11') return _json([]);
        return _json(
          isDev
              ? [
                  session(101, '2026-11-24', [bench, treadmill]),
                  session(100, '2026-11-20', [bench]),
                ]
              : [
                  session(7, '2026-11-20', [bench]),
                  // 11/24 벤치는 이미 옮겨짐 (서버가 같은 날 세션에 이어 붙임)
                  session(8, '2026-11-24', [bench]),
                ],
        );
      }),
    );

    final missing = await service.findMissing([
      DateTime(2026, 11),
      DateTime(2026, 10),
    ]);
    // 11/20 은 통째로 있고, 11/24 는 벤치만 있어 러닝머신만 남음
    expect(missing.map((m) => m.session.id), [101]);
    expect(missing.single.partial, isTrue); // 운영에 11/24 기록이 이미 있음
    expect(
      missing.single.session.exercises.map((e) => e.exerciseItemId),
      [872],
    );

    // '다시 안 보기'로 뺀 운동은 목록에 안 뜸
    final hidden = await service.findMissing(
      [DateTime(2026, 11)],
      ignored: {
        DevImportService.keyOf(
          missing.single.session.date,
          missing.single.session.exercises.single,
        ),
      },
    );
    expect(hidden, isEmpty);

    await service.copyToProd(missing.single.session);
    expect(posted!['sessionDate'], '2026-11-24');
    expect(posted!['exercises'], [
      {
        'exerciseItemId': 872,
        'durationMin': 30.0,
        'distanceKm': null,
        'kcal': 250,
        'avgHr': null,
        'memo': '경사 12% · 속도 5.5km/h',
        'sets': <Object>[],
      },
    ]);
  });

  test('개발 서버 일기 옮기기: 운영에 없는 날만, 메모 → 초안 → 최종본 덮어쓰기 → 비공개 게시', () async {
    final calls = <String>[];
    final bodies = <String, Object?>{};
    final service = DevImportService(
      devBase: 'http://dev.test:8081',
      client: MockClient((req) async {
        final dev = req.url.host == 'dev.test';
        final key = '${dev ? 'dev' : 'prod'} ${req.method} ${req.url.path}';
        calls.add(key);
        if (req.body.isNotEmpty) bodies[key] = jsonDecode(req.body);
        return switch (key) {
          'dev GET /api/diary/recent' => _json([
            {'date': '2026-11-24', 'notes': 2, 'diary': 'published'},
            {'date': '2026-11-20', 'notes': 1, 'diary': null},
          ]),
          'prod GET /api/diary/recent' => _json([
            {'date': '2026-11-20', 'notes': 1, 'diary': null},
          ]),
          'dev GET /api/diary/2026-11-24' => _json({
            'date': '2026-11-24',
            'notes': [
              {'id': 1, 'source': 'app', 'fileName': 'a.md', 'content': '산책'},
              {'id': 2, 'source': 'manual', 'fileName': null, 'content': '저녁'},
            ],
            'diary': {
              'id': 9,
              'title': '산책한 날',
              'content': '고친 최종본',
              'status': 'published',
            },
          }),
          'dev GET /api/diary/2026-11-20' => _json({
            'date': '2026-11-20',
            'notes': [
              {'id': 3, 'source': 'app', 'content': '메모'},
            ],
            'diary': null,
          }),
          'prod POST /api/diary/2026-11-24/generate' => _json({
            'diary': {'id': 77, 'title': 'AI 초안', 'content': '...'},
          }),
          _ => _json({}),
        };
      }),
    );

    final list = await service.findMissingDiaries();
    expect(list.map((d) => d.date), ['2026-11-24', '2026-11-20']);
    expect(list.first.partial, isFalse);
    expect(list.last.partial, isTrue); // 운영에 11/20 메모가 이미 있음
    expect(list.first.summary, '메모 2개 · 게시한 일기 · 「산책한 날」');

    calls.clear();
    await service.copyDiary(list.first, private: true);
    expect(calls, [
      'prod POST /api/diary/2026-11-24/notes',
      'prod POST /api/diary/2026-11-24/notes',
      'prod POST /api/diary/2026-11-24/generate',
      'prod PUT /api/diary/entries/77',
      'prod POST /api/diary/entries/77/publish',
    ]);
    expect(bodies['prod PUT /api/diary/entries/77'], {
      'title': '산책한 날',
      'content': '고친 최종본',
    });
    expect(bodies['prod POST /api/diary/entries/77/publish'], {
      'subId': null,
      'visibility': 'private',
    });
  });

  testWidgets('피팅 추가: 직전 피팅 값을 채워 두고, 바꾼 값으로 저장', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    Map<String, dynamic>? sent;
    final api = BikeApi(
      client: MockClient((req) async {
        expect(req.method, 'POST');
        expect(req.url.path, '/api/bikes/6/fits');
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return _json({'id': 2});
      }),
    );
    final previous = BikeFit.fromJson({
      'id': 1,
      'bikeId': 6,
      'fitDate': '2026-07-01',
      'fitter': '피팅스타',
      'saddleHeightMm': 712.5,
      'crankLengthMm': 170,
      'cleatLeft': '노랑 6°',
    });

    var popped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  popped =
                      await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => BikeFitFormScreen(
                            bike: const Bike(id: 6, name: 'GTR PRO TE'),
                            api: api,
                            color: Colors.purple,
                            previous: previous,
                            now: DateTime(2026, 11, 28),
                          ),
                        ),
                      ) ??
                      false;
                },
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    expect(find.text('2026.11.28'), findsOneWidget);
    expect(find.text('2025.07.01'), findsNothing);
    // 직전 값이 채워져 있음
    expect(find.widgetWithText(TextField, '712.5'), findsOneWidget);
    expect(find.widgetWithText(TextField, '170'), findsOneWidget);

    // 크랭크를 165 로 바꾸고 저장
    await tester.enterText(find.widgetWithText(TextField, '170'), '165');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(sent!['fitDate'], '2026-11-28');
    expect(sent!['fitter'], '피팅스타');
    expect(sent!['saddleHeightMm'], 712.5);
    expect(sent!['crankLengthMm'], 165.0);
    expect(sent!['cleatLeft'], '노랑 6°');
    expect(sent!['reachMm'], isNull);
    expect(popped, isTrue);
  });
}
