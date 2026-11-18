import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lifemetrics_app/models/persona.dart';
import 'package:lifemetrics_app/screens/human/diary_screen.dart';
import 'package:lifemetrics_app/services/api_client.dart';
import 'package:lifemetrics_app/services/daily_events.dart';
import 'package:lifemetrics_app/services/diary_api.dart';
import 'package:lifemetrics_app/services/fitness_api.dart';
import 'package:lifemetrics_app/services/ride_api.dart';

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  final day = DateTime(2026, 11, 18);

  group('DiaryApi', () {
    test('토큰을 싣고 날짜 경로로 읽으며, 없으면 null', () async {
      final seen = <http.Request>[];
      final api = DiaryApi(
        token: 'secret',
        client: MockClient((req) async {
          seen.add(req);
          if (req.url.path.endsWith('2026-11-17')) {
            return _json({'message': '그날 일기가 없습니다.'}, 404);
          }
          return _json({
            'date': '2026-11-18',
            'postId': 1,
            'title': '11월 18일 (수)',
            'body': '본문',
            'visibility': 'private',
          });
        }),
      );

      final d = await api.fetch(day);
      expect(d!.body, '본문');
      expect(d.isPublic, isFalse);
      expect(seen.single.url.path, '/api/diary/2026-11-18');
      expect(seen.single.headers['Authorization'], 'Bearer secret');

      expect(await api.fetch(DateTime(2026, 11, 17)), isNull);
    });

    test('저장은 PUT 으로 본문 · 공개 여부를 보냄', () async {
      late http.Request sent;
      final api = DiaryApi(
        token: 'secret',
        client: MockClient((req) async {
          sent = req;
          final b = jsonDecode(req.body) as Map;
          return _json({'date': '2026-11-18', ...b});
        }),
      );

      final d = await api.save(day, body: '오늘 생각', isPublic: true);
      expect(sent.method, 'PUT');
      expect(jsonDecode(sent.body), {
        'title': null,
        'body': '오늘 생각',
        'visibility': 'public',
      });
      expect(d.isPublic, isTrue);
    });

    test('토큰이 없으면 요청하지 않고, 401 은 알아볼 수 있는 문구로', () async {
      var calls = 0;
      final noToken = DiaryApi(
        token: '',
        client: MockClient((_) async {
          calls++;
          return _json({});
        }),
      );
      await expectLater(noToken.fetch(day), throwsA(isA<ApiException>()));
      expect(calls, 0);

      final wrong = DiaryApi(
        token: 'x',
        client: MockClient((_) async => _json({'message': 'no'}, 401)),
      );
      await expectLater(
        wrong.fetch(day),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('토큰'),
          ),
        ),
      );
    });
  });

  test('종합 분석 이벤트에 그날 일기가 인간 이벤트로 들어감', () async {
    final source = DailyEventSource(
      fitness: FitnessApi(client: MockClient((_) async => _json([]))),
      rides: RideApi(client: MockClient((_) async => _json([]))),
      diary: DiaryApi(
        token: 'secret',
        client: MockClient(
          (_) async => _json({
            'date': '2026-11-18',
            'title': '',
            'body': '\n  아침에 철학책을 읽었다\n두 번째 줄',
            'visibility': 'private',
          }),
        ),
      ),
    );

    final data = await source.load(day);
    final e = data.events.singleWhere((e) => e.persona == Persona.human);
    expect(e.title, '하루 일기');
    expect(e.detail, '아침에 철학책을 읽었다');
    expect(data.connected, contains(Persona.human));
  });

  testWidgets('일기 화면: 그날 일기를 불러오고, 고쳐서 저장', (tester) async {
    // 폰처럼 세로로 긴 화면 (기본 800x600 이면 저장 버튼이 화면 밖)
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final puts = <Map>[];
    final api = DiaryApi(
      token: 'secret',
      client: MockClient((req) async {
        if (req.method == 'PUT') {
          final b = jsonDecode(req.body) as Map;
          puts.add(b);
          return _json({'date': '2026-11-18', 'title': '11월 18일 (수)', ...b});
        }
        return _json({
          'date': '2026-11-18',
          'title': '11월 18일 (수)',
          'body': '처음 쓴 일기',
          'visibility': 'private',
        });
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DiaryScreen(api: api, now: day)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('11월 18일 (수) · 오늘'), findsOneWidget);
    expect(find.text('처음 쓴 일기'), findsOneWidget);
    expect(find.text('저장됨'), findsOneWidget);

    await tester.enterText(find.text('처음 쓴 일기'), '고친 일기');
    await tester.pump();
    expect(find.text('고친 내용이 아직 저장되지 않았어요'), findsOneWidget);

    await tester.tap(find.text('고친 내용 저장'));
    await tester.pumpAndSettle();

    expect(puts.single['body'], '고친 일기');
    expect(puts.single['visibility'], 'private');
    expect(find.text('저장됨'), findsOneWidget);
  });
}
