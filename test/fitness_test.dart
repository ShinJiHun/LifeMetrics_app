import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lifemetrics_app/screens/athlete/fitness/workout_history_screen.dart';
import 'package:lifemetrics_app/screens/athlete/fitness/workout_input_screen.dart';
import 'package:lifemetrics_app/services/fitness_api.dart';

// 한글 본문이라 UTF-8 바이트로 응답 (http.Response 문자열 생성자는 latin1)
http.Response utf8Response(
  String body,
  int status, {
  Map<String, String> headers = const {},
}) => http.Response.bytes(utf8.encode(body), status, headers: headers);

void main() {
  final now = DateTime(2026, 8, 30);

  // 서버 /api/exercise/history 한 건 형태
  Map<String, dynamic> session(int id, String date, {bool pt = false}) => {
    'id': id,
    'sessionDate': date,
    'isPT': pt,
    'memo': null,
    'totalVolume': 3820.0,
    'totalSets': 2,
    'estimatedMinutes': 24,
    'estimatedCalories': 180.0,
    'logs': [
      {
        'id': id * 10,
        'exerciseItemId': 31,
        'exerciseNameKo': '덤벨 벤치 프레스',
        'categoryName': '가슴',
        'sets': [
          {'id': 2, 'setNumber': 2, 'weight': 14.0, 'reps': 12},
          {'id': 1, 'setNumber': 1, 'weight': 12.5, 'reps': 15},
        ],
      },
    ],
  };

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: screen,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('기록: 이번 달 세션 → 펼치면 세트, 이전 달로 이동', (tester) async {
    final months = <String?>[];
    final client = MockClient((req) async {
      if (req.url.path == '/api/ai/analysis/exercise/208') {
        return utf8Response(
          jsonEncode({
            'summary': '가슴 집중 PT 세션',
            'score': 72,
            'volumeLevel': '보통',
            'intensityLevel': '높음',
            'highlights': ['점진적 증량'],
            'suggestions': ['휴식 시간 기록'],
          }),
          200,
        );
      }
      months.add(req.url.queryParameters['month']);
      final list = req.url.queryParameters['month'] == '2026-08'
          ? [session(208, '2026-08-26', pt: true)]
          : [];
      return utf8Response(jsonEncode(list), 200);
    });
    await pump(
      tester,
      WorkoutHistoryScreen(
        api: FitnessApi(client: client),
        now: now,
      ),
    );

    expect(months, ['2026-08']);
    expect(find.text('2026년 8월'), findsOneWidget);
    expect(find.text('8/26 (수)'), findsOneWidget);
    expect(find.text('PT'), findsOneWidget);
    expect(find.text('덤벨 벤치 프레스  ·  2세트'), findsOneWidget);

    await tester.tap(find.text('8/26 (수)'));
    await tester.pumpAndSettle();
    expect(find.text('덤벨 벤치 프레스'), findsOneWidget);
    // 세트 번호순으로 정렬돼 보임
    expect(find.textContaining('12.5kg × 15'), findsOneWidget);
    expect(find.text('가슴 집중 PT 세션'), findsOneWidget);
    expect(find.text('72점'), findsOneWidget);
    expect(find.text('볼륨 보통 · 강도 높음'), findsOneWidget);
    expect(find.text('점진적 증량'), findsOneWidget);
    expect(find.text('휴식 시간 기록'), findsOneWidget);

    // 이번 달보다 뒤로는 못 감
    final next = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right),
    );
    expect(next.onPressed, isNull);

    await tester.tap(find.byTooltip('이전 달'));
    await tester.pumpAndSettle();
    expect(months.last, '2026-07');
    expect(find.text('이 달엔 운동 기록이 없어요'), findsOneWidget);
  });

  testWidgets('입력: 종목 고르기 → 세트 입력 → 관리자 로그인 후 저장', (tester) async {
    Map<String, dynamic>? saved;
    var loggedIn = false;
    final client = MockClient((req) async {
      switch (req.url.path) {
        case '/api/exercise/categories':
          return utf8Response(
            jsonEncode([
              {'id': 1, 'name': '가슴'},
              {'id': 5, 'name': '하체'},
            ]),
            200,
          );
        case '/api/exercise/items':
          return utf8Response(
            jsonEncode([
              {
                'id': 31,
                'categoryId': 1,
                'nameKo': '덤벨 벤치 프레스',
                'nameEn': 'Dumbbell Bench Press',
                'equipmentType': 'FREE_WEIGHT',
              },
              {
                'id': 70,
                'categoryId': 5,
                'nameKo': '스쿼트',
                'nameEn': 'Squat',
                'equipmentType': 'FREE_WEIGHT',
              },
            ]),
            200,
          );
        case '/api/admin/login':
          loggedIn = true;
          return utf8Response(
            '{"admin":true}',
            200,
            headers: {'set-cookie': 'JSESSIONID=fit; Path=/'},
          );
        case '/api/exercise/log':
          if (!loggedIn) {
            return utf8Response('{"code":"ADMIN_REQUIRED"}', 403);
          }
          expect(req.headers['Cookie'], 'JSESSIONID=fit');
          saved = jsonDecode(req.body) as Map<String, dynamic>;
          return utf8Response('', 200);
      }
      return utf8Response('not found', 404);
    });
    await pump(
      tester,
      WorkoutInputScreen(
        api: FitnessApi(client: client),
        now: now,
      ),
    );

    await tester.tap(find.text('운동 추가'));
    await tester.pumpAndSettle();
    // 부위 칩으로 거르기
    await tester.tap(find.widgetWithText(ChoiceChip, '하체'));
    await tester.pumpAndSettle();
    expect(find.text('덤벨 벤치 프레스'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '전체'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'bench');
    await tester.pumpAndSettle();
    expect(find.text('스쿼트'), findsNothing);
    await tester.tap(find.text('덤벨 벤치 프레스'));
    await tester.pumpAndSettle();

    // 1세트 입력 → 세트 추가하면 같은 값으로 채워짐
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '12.5');
    await tester.enterText(fields.at(1), '15');
    await tester.tap(find.text('세트 추가'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(4));
    await tester.enterText(find.byType(TextField).at(2), '14');

    await tester.tap(find.widgetWithText(SwitchListTile, 'PT 수업'));
    await tester.tap(find.text('저장'));
    // 저장 중 스피너가 돌아 settle 되지 않으니 다이얼로그가 뜰 만큼만
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('관리자 로그인'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'pw',
    );
    await tester.tap(find.text('로그인'));
    await tester.pumpAndSettle();

    expect(saved, {
      'sessionDate': '2026-08-30',
      'userId': 1,
      'isPT': true,
      'exercises': [
        {
          'exerciseItemId': 31,
          'restTimeSec': 60,
          'memo': null,
          'sets': [
            {'setNumber': 1, 'weight': 12.5, 'reps': 15},
            {'setNumber': 2, 'weight': 14.0, 'reps': 15},
          ],
        },
      ],
    });
    expect(find.text('운동을 저장했어요'), findsOneWidget);
    expect(find.text('운동을 추가해 주세요'), findsOneWidget);
  });

  testWidgets('입력: 횟수가 비면 저장하지 않음', (tester) async {
    var posted = false;
    final client = MockClient((req) async {
      if (req.url.path == '/api/exercise/log') posted = true;
      return utf8Response(
        req.url.path.endsWith('items')
            ? jsonEncode([
                {'id': 1, 'categoryId': 1, 'nameKo': '푸쉬업'},
              ])
            : '[]',
        200,
      );
    });
    await pump(
      tester,
      WorkoutInputScreen(
        api: FitnessApi(client: client),
        now: now,
      ),
    );
    await tester.tap(find.text('운동 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('푸쉬업'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.text('모든 세트에 횟수를 입력해 주세요'), findsOneWidget);
    expect(posted, isFalse);
  });
}
