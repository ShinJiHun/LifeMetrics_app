import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lifemetrics_app/models/ride.dart';
import 'package:lifemetrics_app/screens/athlete/body/health_checkup_form_screen.dart';
import 'package:lifemetrics_app/services/health_checkup_api.dart';
import 'package:lifemetrics_app/services/home_widget_service.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('홈 위젯: 이번 주(월요일부터) 라이딩 거리만 더함', () {
    final thursday = DateTime(2026, 11, 26, 9);
    final rides = [
      Ride(id: 1, startTime: DateTime(2026, 11, 26, 7), distanceMeters: 30500),
      Ride(id: 2, startTime: DateTime(2026, 11, 23, 0, 30), distanceMeters: 12000),
      Ride(id: 3, startTime: DateTime(2026, 11, 22, 18), distanceMeters: 99000),
      Ride(id: 4, startTime: DateTime(2026, 11, 24)),
    ];
    expect(HomeWidgetService.weekRideKm(rides, thursday), closeTo(42.5, 1e-9));
  });

  test('건강검진 PDF: multipart file 로 /extract, 422 이유는 그대로', () async {
    late http.BaseRequest sent;
    var fail = false;
    final api = HealthCheckupApi(
      client: MockClient.streaming((req, body) async {
        sent = req;
        final bytes = await body.toBytes();
        expect(utf8.decode(bytes, allowMalformed: true), contains('result.pdf'));
        final res = fail
            ? _json({'message': 'PDF에서 텍스트를 읽지 못했습니다.'}, 422)
            : _json({'checkupDate': '2025-11-03', 'systolicBp': 118});
        return http.StreamedResponse(
          Stream.value(res.bodyBytes),
          res.statusCode,
          headers: res.headers,
        );
      }),
    );

    final read = await api.extract([1, 2, 3], 'result.pdf');
    expect(sent.url.path, '/api/body/health-checkups/extract');
    expect(read['systolicBp'], 118);

    fail = true;
    await expectLater(
      api.extract([1], 'result.pdf'),
      throwsA(
        predicate(
          (e) => e.toString().contains('PDF에서 텍스트를 읽지 못했습니다.'),
        ),
      ),
    );
  });

  testWidgets('검진 검토 화면: AI 값을 채워 두고, 고친 값 + 화면에 없는 항목까지 저장', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    Map<String, dynamic>? saved;
    final api = HealthCheckupApi(
      client: MockClient((req) async {
        expect(req.method, 'POST');
        expect(req.url.path, '/api/body/health-checkups');
        saved = jsonDecode(req.body) as Map<String, dynamic>;
        return _json({'id': 3});
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: HealthCheckupFormScreen(
          api: api,
          color: Colors.pink,
          fromPdf: true,
          initial: const {
            'checkupDate': '2025-11-03',
            'checkupPlace': '서울 검진센터',
            'overallJudgment': '정상B',
            'systolicBp': 118,
            'fastingBloodSugar': 96,
            'visionLeft': 1.0,
            'rawText': '원문',
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2025.11.03'), findsOneWidget);
    expect(find.widgetWithText(TextField, '서울 검진센터'), findsOneWidget);

    // AI 가 잘못 읽은 공복혈당을 고침
    await tester.enterText(find.widgetWithText(TextField, '96'), '92');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(saved!['id'], isNull);
    expect(saved!['checkupDate'], '2025-11-03');
    expect(saved!['checkupPlace'], '서울 검진센터');
    expect(saved!['systolicBp'], 118.0);
    expect(saved!['fastingBloodSugar'], 92.0);
    expect(saved!['ldlCholesterol'], isNull);
    expect(saved!['visionLeft'], 1.0); // 화면에 없는 항목도 그대로
    expect(saved!['rawText'], '원문');
  });
}
