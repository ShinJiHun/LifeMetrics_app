import 'dart:convert';
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';

import 'package:lifemetrics_app/models/body_analysis.dart';
import 'package:lifemetrics_app/models/body_record.dart';
import 'package:lifemetrics_app/screens/athlete/body/inbody_screen.dart';
import 'package:lifemetrics_app/services/body_api.dart';

void main() {
  Future<void> pumpInbody(WidgetTester tester, http.Client client) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: InbodyScreen(api: BodyApi(client: client)),
      ),
    );
    await tester.pumpAndSettle();
  }

  // 서버 BodyRecordsResponse 형태로 응답
  http.Client serve(List<Map<String, dynamic>> records) =>
      MockClient((req) async {
        expect(req.url.path, '/api/body/records');
        expect(req.url.queryParameters['userId'], '1');
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'records': records,
              'latest': records.isEmpty ? null : records.last,
            }),
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

  Map<String, dynamic> inbody(
    int id,
    String date, {
    required double weight,
    double? muscle,
    double? fat,
    double? fatFree,
    double? fatPercent,
  }) => {
    'id': id,
    'recordDate': date,
    'measurementType': 'INBODY',
    'weight': weight,
    'skeletalMuscleMass': muscle,
    'bodyFatMass': fat,
    'fatFreeMass': fatFree,
    'bodyFatPercentage': fatPercent,
  };

  test('BodyRecord: 기록지 값 우선, 없으면 계산', () {
    final stored = BodyRecord.fromJson(
      inbody(1, '2022-07-11', weight: 81.4, fat: 19.5, fatFree: 61.8),
    );
    expect(stored.leanMass, 61.8);
    expect(stored.bodyFatPercent, closeTo(23.96, 0.01));

    final withPercent = BodyRecord.fromJson(
      inbody(2, '2022-07-11', weight: 81.4, fat: 19.5, fatPercent: 24.0),
    );
    expect(withPercent.bodyFatPercent, 24.0);
    expect(withPercent.leanMass, closeTo(61.9, 0.001));
  });

  testWidgets('서버 연결 실패 → 다시 시도', (tester) async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      if (calls == 1) throw http.ClientException('down');
      return http.Response('{"records":[],"latest":null}', 200);
    });
    await pumpInbody(tester, client);

    expect(find.text('서버에 연결할 수 없어요'), findsOneWidget);
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('아직 FitDays 기록이 없어요'), findsOneWidget);
  });

  testWidgets('요약 · 증감 색 · 제지방량 · 기간 필터', (tester) async {
    await pumpInbody(
      tester,
      serve([
        inbody(1, '2025-01-10', weight: 80, muscle: 35, fat: 18, fatFree: 62),
        {
          'id': 9,
          'recordDate': '2026-08-20',
          'measurementType': 'FITDAYS',
          'weight': 90.0,
          'bodyFatPercentage': 30.0,
        },
        inbody(2, '2026-08-01', weight: 81, muscle: 35.6, fat: 18.6),
        inbody(3, '2026-09-01', weight: 81.4, muscle: 35.6, fat: 19.5),
      ]),
    );

    expect(find.text('인바디 3'), findsOneWidget);
    expect(find.text('FitDays 1'), findsOneWidget);
    expect(find.text('최근 측정 · 2026.09.01'), findsOneWidget);
    expect(find.text('81.4 kg', findRichText: true), findsOneWidget);
    // 제지방량 = 81.4 - 19.5
    expect(find.text('61.9 kg', findRichText: true), findsOneWidget);

    Color colorOf(String text) =>
        tester.widget<Text>(find.text(text)).style!.color!;
    // 증감은 같은 측정 종류끼리만 비교 (FitDays 90kg 는 무시)
    expect(colorOf('▲ 0.4 kg'), Colors.white.withValues(alpha: 0.6));
    expect(colorOf('▲ 0.9 kg'), const Color(0xFFF09595)); // 체지방량 증가
    expect(colorOf('▼ 0.5 kg'), const Color(0xFFF09595)); // 제지방량 감소
    expect(find.text('— 변화 없음'), findsOneWidget); // 골격근량

    int spots() => tester
        .widget<LineChart>(find.byType(LineChart))
        .data
        .lineBarsData
        .single
        .spots
        .length;

    expect(spots(), 3);
    await tester.scrollUntilVisible(
      find.text('3개월'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('3개월'));
    await tester.pumpAndSettle();
    expect(spots(), 2);
  });

  testWidgets('FitDays: 없는 지표는 타일·차트 선택에서 빠짐', (tester) async {
    Map<String, dynamic> fitdays(int id, String date, double w, double p) => {
      'id': id,
      'recordDate': date,
      'measurementType': 'FITDAYS',
      'weight': w,
      'bodyFatPercentage': p,
    };
    await pumpInbody(
      tester,
      serve([
        fitdays(1, '2026-09-01', 82, 25),
        fitdays(2, '2026-09-08', 81.5, 24.4),
      ]),
    );

    // 인바디 기록이 없으면 FitDays 탭으로 시작
    expect(find.text('최근 측정 · 2026.09.08'), findsOneWidget);
    expect(find.text('골격근량'), findsNothing);
    expect(find.text('제지방량'), findsNothing);
    expect(find.text('24.4 %', findRichText: true), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('▼ 0.6 %')).style!.color,
      const Color(0xFF5DCAA5),
    );

    await tester.tap(find.text('인바디 0'));
    await tester.pumpAndSettle();
    expect(find.text('아직 인바디 기록이 없어요'), findsOneWidget);
  });

  test('BodyAnalysis: 코드블록 감싼 JSON · 잘못된 값', () {
    final a = BodyAnalysis.tryParse('''
```json
{"summary": "체지방 증가", "current_evaluation": {"muscle": "정체", "fat": ""},
 "recommendations": ["유산소", 3, "단백질"]}
```''');
    expect(a!.summary, '체지방 증가');
    expect(a.muscle, '정체');
    expect(a.fat, isNull);
    expect(a.trend, isNull);
    expect(a.recommendations, ['유산소', '단백질']);

    expect(BodyAnalysis.tryParse(null), isNull);
    expect(BodyAnalysis.tryParse('분석 실패'), isNull);
    expect(BodyAnalysis.tryParse('{"trend": "요약 없음"}'), isNull);
  });

  testWidgets('AI 분석 카드 → 시트', (tester) async {
    final record =
        inbody(1, '2026-08-06', weight: 81.4, muscle: 35.6, fat: 19.5)
          ..['rawLlmJson'] = jsonEncode({
            'summary': '체중은 유지, 체지방은 증가',
            'current_evaluation': {
              'muscle': '골격근량 35.6kg 정체',
              'fat': '체지방률 24%',
              'overall': 'BMI 29.2',
            },
            'trend': '66일간 체지방 +0.9kg',
            'recommendations': ['유산소 늘리기', '근력 강도 높이기'],
          });
    await pumpInbody(tester, serve([record]));

    await tester.tap(find.text('체중은 유지, 체지방은 증가'));
    await tester.pumpAndSettle();

    expect(find.text('AI 분석'), findsOneWidget);
    expect(find.text('2026.08.06 측정'), findsOneWidget);
    expect(find.text('골격근량 35.6kg 정체'), findsOneWidget);
    expect(find.text('66일간 체지방 +0.9kg'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('근력 강도 높이기'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('근력 강도 높이기'), findsOneWidget);
  });

  testWidgets('분석이 없으면 카드도 없음', (tester) async {
    await pumpInbody(tester, serve([inbody(1, '2026-08-06', weight: 81.4)]));
    expect(find.byIcon(Icons.auto_awesome), findsNothing);
  });

  testWidgets('업로드: 사진 고르기 → multipart 전송 → 다시 불러옴', (tester) async {
    var recordsCalls = 0;
    http.BaseRequest? upload;
    final client = MockClient.streaming((req, body) async {
      if (req.url.path == '/api/body/inbody/upload') {
        upload = req;
        await body.drain<void>();
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"success":true,"message":"ok"}')),
          200,
        );
      }
      recordsCalls++;
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"records":[],"latest":null}')),
        200,
      );
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    ImageSource? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: InbodyScreen(
          api: BodyApi(client: client),
          pickImage: (source) async {
            picked = source;
            return XFile.fromData(
              Uint8List.fromList([1, 2, 3]),
              name: 'inbody.jpg',
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(recordsCalls, 1);

    await tester.tap(find.byTooltip('기록지 업로드'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('사진에서 고르기'));
    await tester.pump();
    await tester.pump();

    expect(picked, ImageSource.gallery);
    final req = upload as http.MultipartRequest;
    expect(req.method, 'POST');
    expect(req.fields['type'], 'INBODY');
    expect(req.files.single.field, 'file');
    expect(req.files.single.filename, 'inbody.jpg');
    expect(find.text('업로드했어요. 잠시 후 기록에 반영돼요'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(recordsCalls, 2);
  });

  testWidgets('업로드: 서버가 success false 면 메시지', (tester) async {
    final client = MockClient.streaming((req, body) async {
      await body.drain<void>();
      final json = req.url.path == '/api/body/inbody/upload'
          ? '{"success":false,"message":"인식 실패"}'
          : '{"records":[],"latest":null}';
      return http.StreamedResponse(Stream.value(utf8.encode(json)), 200);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: InbodyScreen(
          api: BodyApi(client: client),
          pickImage: (_) async =>
              XFile.fromData(Uint8List.fromList([1]), name: 'a.jpg'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('기록지 업로드'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카메라로 찍기'));
    await tester.pumpAndSettle();
    expect(find.text('업로드에 실패했어요: 인식 실패'), findsOneWidget);
  });

  // 업로드는 관리자 쿠키가 있어야 통과, 로그인 비밀번호는 'pw'
  MockClient adminServer(List<String?> uploadCookies) => MockClient.streaming((
    req,
    body,
  ) async {
    final text = await utf8.decodeStream(body);
    http.StreamedResponse json(String s, int code, [Map<String, String>? h]) =>
        http.StreamedResponse(
          Stream.value(utf8.encode(s)),
          code,
          headers: h ?? {},
        );
    switch (req.url.path) {
      case '/api/admin/login':
        return jsonDecode(text)['password'] == 'pw'
            ? json('{"admin":true}', 200, {
                'set-cookie': 'JSESSIONID=abc; Path=/; HttpOnly',
              })
            : json('{"admin":false}', 401);
      case '/api/body/inbody/upload':
        final cookie = req.headers['Cookie'];
        uploadCookies.add(cookie);
        return cookie == 'JSESSIONID=abc'
            ? json('{"success":true}', 200)
            : json('{"error":"x","code":"ADMIN_REQUIRED"}', 403);
      default:
        return json('{"records":[],"latest":null}', 200);
    }
  });

  Future<void> pumpUpload(WidgetTester tester, http.Client client) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: InbodyScreen(
          api: BodyApi(client: client),
          pickImage: (_) async =>
              XFile.fromData(Uint8List.fromList([1]), name: 'a.png'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('기록지 업로드'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('사진에서 고르기'));
    // 업로드 중 스피너가 돌아 settle 되지 않으니 다이얼로그가 뜰 만큼만
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('업로드: 비밀번호가 틀리면 다시 보내지 않음', (tester) async {
    final cookies = <String?>[];
    await pumpUpload(tester, adminServer(cookies));
    expect(find.text('관리자 로그인'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'nope');
    await tester.tap(find.text('로그인'));
    await tester.pumpAndSettle();
    expect(find.text('비밀번호가 올바르지 않아요'), findsOneWidget);
    expect(cookies, [null]);
  });

  testWidgets('업로드: 관리자 필요 → 로그인 → 쿠키 붙여 다시 보냄', (tester) async {
    final cookies = <String?>[];
    await pumpUpload(tester, adminServer(cookies));

    await tester.enterText(find.byType(TextField), 'pw');
    await tester.tap(find.text('로그인'));
    await tester.pump();
    await tester.pump();
    expect(cookies, [null, 'JSESSIONID=abc']);
    expect(find.text('업로드했어요. 잠시 후 기록에 반영돼요'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
