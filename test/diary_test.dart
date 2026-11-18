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

http.Response _json(Object? body, [int status = 200, Map<String, String>? h]) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8', ...?h},
    );

final _forbidden = _json({'message': '관리자만 접근할 수 있습니다.'}, 403);

Map<String, Object?> _day({
  List<Map<String, Object?>> notes = const [],
  Map<String, Object?>? diary,
}) => {
  'date': '2026-11-18',
  'notes': notes,
  'diary': diary,
  'book': null,
  'records': {
    'rides': [1],
  },
};

const _note = {
  'id': 5,
  'noteDate': '2026-11-18',
  'source': 'app',
  'fileName': null,
  'content': '\n점심에 산책하며 자유의지에 대해 생각했다\n둘째 줄',
  'createdAt': '2026-11-18T12:40:00',
};

const _draft = {
  'id': 9,
  'entryDate': '2026-11-18',
  'kind': 'diary',
  'title': '산책과 자유의지',
  'content': '오늘은 점심에 산책을 했다.',
  'warnings': ['회사 이름이 들어 있어요'],
  'status': 'draft',
  'edited': false,
  'postId': null,
  'generatedAt': '2026-11-18T22:00:00',
  'publishedAt': null,
};

// 관리자 로그인 응답. 쿠키를 받아야 다음 요청에 실림
http.Response _loginOk() =>
    _json({'admin': true}, 200, {'set-cookie': 'lm_admin=abc; Path=/'});

void main() {
  final day = DateTime(2026, 11, 18);

  group('DiaryApi', () {
    test('로그인 전 403 은 AdminRequiredException, 로그인하면 쿠키를 싣고 하루를 읽음', () async {
      var loggedIn = false;
      final api = DiaryApi(
        client: MockClient((req) async {
          if (req.url.path == '/api/admin/login') {
            loggedIn = true;
            return _loginOk();
          }
          if (!loggedIn) return _forbidden;
          expect(req.headers['Cookie'], 'lm_admin=abc');
          return _json(_day(notes: [_note], diary: _draft));
        }),
      );

      await expectLater(
        api.fetchDay(day),
        throwsA(isA<AdminRequiredException>()),
      );
      expect(await api.loginAdmin('pw'), isTrue);

      final d = await api.fetchDay(day);
      expect(d.notes.single.sourceLabel, 'Claude 앱');
      expect(d.notes.single.createdAt, DateTime(2026, 11, 18, 12, 40));
      expect(d.diary!.title, '산책과 자유의지');
      expect(d.diary!.warnings, ['회사 이름이 들어 있어요']);
      expect(d.recordKinds, ['라이딩']);
    });

    test('메모 추가 · 게시 요청 본문, 서버 message 는 그대로 보여줌', () async {
      final sent = <http.Request>[];
      final api = DiaryApi(
        client: MockClient((req) async {
          sent.add(req);
          if (req.url.path.endsWith('/notes')) return _json(_note);
          if (req.url.path.endsWith('/publish')) {
            return _json({..._draft, 'status': 'published', 'postId': 3});
          }
          return _json({'message': '이 날짜에는 메모도 운동 기록도 없습니다.'}, 400);
        }),
      );

      await api.addNote(day, '오늘 생각');
      expect(sent.last.url.path, '/api/diary/2026-11-18/notes');
      expect(jsonDecode(sent.last.body), {'source': 'app', 'content': '오늘 생각'});

      final e = await api.publish(9, subId: 20);
      expect(sent.last.url.path, '/api/diary/entries/9/publish');
      expect(jsonDecode(sent.last.body), {'subId': 20, 'visibility': 'private'});
      expect(e.isPublished, isTrue);

      await expectLater(
        api.generate(day),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            '이 날짜에는 메모도 운동 기록도 없습니다.',
          ),
        ),
      );
    });
  });

  group('종합 분석 이벤트', () {
    DailyEventSource source(MockClient diary) => DailyEventSource(
      fitness: FitnessApi(client: MockClient((_) async => _json([]))),
      rides: RideApi(client: MockClient((_) async => _json([]))),
      diary: DiaryApi(client: diary),
    );

    test('메모는 저장 시각에, 일기 초안은 하루 이벤트로', () async {
      final data = await source(
        MockClient((_) async => _json(_day(notes: [_note], diary: _draft))),
      ).load(day);

      final human = data.events.where((e) => e.persona == Persona.human);
      expect(human.length, 2);
      final note = human.firstWhere((e) => e.time != null);
      expect(note.title, '메모 · Claude 앱');
      expect(note.detail, '점심에 산책하며 자유의지에 대해 생각했다');
      final diary = human.firstWhere((e) => e.time == null);
      expect(diary.title, '산책과 자유의지');
      expect(diary.detail, startsWith('초안 · '));
      expect(data.locked, isEmpty);
    });

    test('로그인 전이면 실패가 아니라 잠김으로 표시', () async {
      final data = await source(MockClient((_) async => _forbidden)).load(day);
      expect(data.locked, {Persona.human});
      expect(data.failed, isEmpty);
    });
  });

  testWidgets('일기 화면: 열면 로그인을 묻고, 메모 · 초안을 보여주고, 비공개로 게시', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    var loggedIn = false;
    var published = false;
    final requests = <http.Request>[];
    final api = DiaryApi(
      client: MockClient((req) async {
        requests.add(req);
        final path = req.url.path;
        if (path == '/api/admin/login') {
          loggedIn = true;
          return _loginOk();
        }
        if (!loggedIn) return _forbidden;
        if (path == '/api/diary/sub-menus') {
          return _json({
            'subs': [
              {'id': 20, 'category': '일기', 'name': '26년'},
              {'id': 8, 'category': '독서', 'name': '인문학'},
            ],
            'diaryDefault': 20,
          });
        }
        if (path.endsWith('/publish')) {
          published = true;
          return _json({..._draft, 'status': 'published', 'postId': 3});
        }
        return _json(
          _day(
            notes: [_note],
            diary: published
                ? {..._draft, 'status': 'published', 'postId': 3}
                : _draft,
          ),
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DiaryScreen(api: api, now: day)),
      ),
    );
    await tester.pumpAndSettle();

    // 열자마자 비밀번호를 물음
    expect(find.text('관리자 로그인'), findsWidgets);
    await tester.enterText(find.byType(TextField), 'pw');
    await tester.tap(find.text('로그인'));
    await tester.pumpAndSettle();

    expect(find.text('메모 1개'), findsOneWidget);
    expect(find.text('점심에 산책하며 자유의지에 대해 생각했다'), findsOneWidget);
    expect(find.text('Claude 앱 · 12:40'), findsOneWidget);
    expect(find.text('산책과 자유의지'), findsOneWidget);
    expect(find.text('· 회사 이름이 들어 있어요'), findsOneWidget);
    expect(find.textContaining('라이딩'), findsOneWidget);

    await tester.ensureVisible(find.text('블로그에 게시'));
    await tester.tap(find.text('블로그에 게시'));
    await tester.pumpAndSettle();
    expect(find.text('일기 › 26년'), findsOneWidget); // 기본 메뉴
    await tester.tap(find.text('비공개로 게시'));
    await tester.pumpAndSettle();

    final publish = requests.lastWhere((r) => r.url.path.endsWith('/publish'));
    expect(jsonDecode(publish.body), {'subId': 20, 'visibility': 'private'});
    expect(find.text('블로그에 게시함'), findsOneWidget);
    expect(find.text('블로그에 게시'), findsNothing);
  });
}
