import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lifemetrics_app/screens/athlete/body/health_checkup_screen.dart';
import 'package:lifemetrics_app/services/api_client.dart';
import 'package:lifemetrics_app/services/health_checkup_api.dart';

http.Response _json(Object? body, [int status = 200, Map<String, String>? h]) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8', ...?h},
    );

// HealthCheckupController 는 @ResponseStatus(FORBIDDEN) 예외라 스프링 기본 오류 JSON 이 옴
final _forbidden = _json({
  'timestamp': '2026-11-25T06:00:00.000+00:00',
  'status': 403,
  'error': 'Forbidden',
  'path': '/api/body/health-checkups',
}, 403);

const _older = {
  'id': 1,
  'checkupDate': '2024-10-02',
  'checkupPlace': '서울 검진센터',
  'overallJudgment': '정상B(경계)',
  'systolicBp': 128,
  'diastolicBp': 82,
  'bpResult': '고혈압 전단계',
  'fastingBloodSugar': 96,
  'ggt': 41,
};

const _latest = {
  'id': 2,
  'checkupDate': '2025-11-03',
  'checkupPlace': '서울 검진센터',
  'overallJudgment': '정상A',
  'suspectedDisease': null,
  'systolicBp': 118,
  'diastolicBp': 76,
  'bpResult': '정상',
  'fastingBloodSugar': 92,
  'diabetesResult': '정상',
  'ggt': 41,
  'needPhysicalActivity': true,
};

void main() {
  test('로그인 전 스프링 기본 403 도 AdminRequiredException, 목록은 최근 검진이 앞', () async {
    var loggedIn = false;
    final api = HealthCheckupApi(
      client: MockClient((req) async {
        if (req.url.path == '/api/admin/login') {
          loggedIn = true;
          return _json({'admin': true}, 200, {
            'set-cookie': 'lm_admin=abc; Path=/',
          });
        }
        if (!loggedIn) return _forbidden;
        expect(req.headers['Cookie'], 'lm_admin=abc');
        return _json([_older, _latest]);
      }),
    );

    await expectLater(api.fetchAll(), throwsA(isA<AdminRequiredException>()));
    expect(await api.loginAdmin('pw'), isTrue);
    final items = await api.fetchAll();
    expect(items.map((c) => c.id), [2, 1]);
    expect(items.first.value('systolicBp'), 118);
  });

  testWidgets('화면: 최근 검진 요약 · 지난 검진 대비 변화 · 상세', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    final api = HealthCheckupApi(
      client: MockClient((req) async => _json([_older, _latest])),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: HealthCheckupScreen(api: api),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2025.11.03'), findsWidgets);
    expect(find.text('정상A'), findsWidgets);
    expect(find.text('2024.10.02 대비'), findsOneWidget);
    // 수축기 128 → 118
    expect(find.text('118 mmHg'), findsOneWidget);
    expect(find.text('▼ 10'), findsOneWidget);
    expect(find.text('변화 없음'), findsOneWidget); // 감마지티피 41 → 41

    // 검진 기록에서 최근 검진 상세
    await tester.tap(find.byIcon(Icons.event_note).first);
    await tester.pumpAndSettle();
    expect(find.text('118/76 mmHg'), findsOneWidget);
    expect(find.text('신체활동'), findsOneWidget);
    expect(find.text('필요'), findsOneWidget);
  });
}
