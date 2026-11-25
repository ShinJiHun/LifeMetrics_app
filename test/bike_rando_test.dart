import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lifemetrics_app/models/randonneuring.dart';
import 'package:lifemetrics_app/screens/athlete/gear/bike_screen.dart';
import 'package:lifemetrics_app/screens/athlete/riding/randonneuring_screen.dart';
import 'package:lifemetrics_app/services/bike_api.dart';
import 'package:lifemetrics_app/services/randonneuring_api.dart';

http.Response _json(Object? body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: screen));
  await tester.pumpAndSettle();
}

Map<String, Object?> _result(
  int id,
  String date,
  int km, {
  String type = 'BREVET',
  String status = 'FINISHED',
  String? pt,
}) => {
  'id': id,
  'eventDate': date,
  'eventType': type,
  'eventName': '테스트 $km',
  'distanceKm': km,
  'status': status,
  'permanentNo': pt,
  'ridingTimeSec': 36000,
};

void main() {
  group('랜도너스 모델', () {
    test('표준 거리 구간과 올해 슈퍼 랜도너 시리즈', () {
      final items = [
        RandoResult.fromJson(_result(1, '2026-03-07', 203)),
        RandoResult.fromJson(_result(2, '2026-04-04', 305)),
        RandoResult.fromJson(_result(3, '2026-05-02', 410)),
        RandoResult.fromJson(_result(4, '2026-06-06', 610, status: 'DNF')),
        RandoResult.fromJson(_result(5, '2025-06-06', 600)),
        RandoResult.fromJson(
          _result(6, '2026-07-30', 209, type: 'PERMANENT', pt: 'PT-171'),
        ),
      ];
      expect(items.first.nominalKm, 200);
      expect(
        RandoResult.fromJson(_result(9, '2026-01-01', 150)).nominalKm,
        isNull,
      );

      final c = RandoCareer(items, now: DateTime(2026, 11, 25));
      expect(c.starts, 6);
      expect(c.finishes, 5);
      expect(c.finishedKm, 203 + 305 + 410 + 600 + 209);
      expect(c.longest!.distanceKm, 600);
      // 600 은 DNF, 작년 600 과 퍼머넌트는 시리즈에 안 셈
      expect(c.yearBrevets, {200, 300, 400});
      expect(c.yearSr, isFalse);
    });

    test('브레베 일정 거리 필터 구간', () {
      BrevetEvent e(String d) => BrevetEvent.fromJson({
        'date': '01.10',
        'region': '전국',
        'name': 'x',
        'distance': d,
        'hasLink': true,
      });
      expect(e('300').bucket, '300');
      expect(e('1200').bucket, '1000+');
      expect(e('24').bucket, '기타');
      expect(e('').bucket, '기타');
    });
  });

  testWidgets('내 자전거: 목록 → 상세(누적 · 기어 사용 · 피팅)', (tester) async {
    final client = MockClient((req) async {
      switch (req.url.path) {
        case '/api/bikes':
          return _json([
            {
              'id': 6,
              'name': 'GTR PRO TE',
              'brand': '거스토',
              'modelYear': 2026,
              'frameMaterial': '카본',
              'chainringOuter': 50,
              'chainringInner': 34,
              'totalDistance': 2039119.0,
              'totalTime': 365780,
              'totalElapsedTime': 492839,
              'isRetired': false,
              'isDefault': true,
            },
            {
              'id': 5,
              'name': 'SCR 2',
              'totalDistance': 1749076.0,
              'totalTime': 300719,
              'isRetired': true,
            },
          ]);
        case '/api/bikes/6/gear-usage':
          return _json([
            {
              'frontGear': 50,
              'rearGear': 17,
              'terrain': 'FLAT',
              'durationSec': 3000.0,
              'distance': 30000.0,
            },
            {
              'frontGear': 34,
              'rearGear': 28,
              'terrain': 'UPHILL',
              'durationSec': 1000.0,
              'distance': 5000.0,
            },
          ]);
        case '/api/bikes/6/fits':
          return _json([
            {
              'id': 1,
              'bikeId': 6,
              'fitDate': '2026-11-28',
              'fitter': '피팅스타',
              'saddleHeightMm': 712.5,
              'crankLengthMm': 165,
            },
          ]);
      }
      return http.Response('not found', 404);
    });

    await _pump(tester, BikeListScreen(api: BikeApi(client: client)));
    expect(find.text('GTR PRO TE'), findsOneWidget);
    expect(find.text('기본'), findsOneWidget);
    expect(find.text('은퇴한 자전거'), findsOneWidget);
    expect(find.text('2,039 km'), findsOneWidget);

    await tester.tap(find.text('GTR PRO TE'));
    await tester.pumpAndSettle();
    expect(find.text('50/34T'), findsOneWidget);
    expect(find.text('50T'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget); // 50T 3000초 / 전체 4000초
    expect(find.text('50×17'), findsOneWidget);
    expect(find.text('안장 높이'), findsOneWidget);
    expect(find.text('712.5 mm'), findsOneWidget);
    expect(find.text('165 mm'), findsOneWidget);
  });

  testWidgets('랜도너스: 내 기록 요약 → 퍼머넌트 탭에서 완주 코스 표시', (tester) async {
    var permanentsCalled = 0;
    final client = MockClient((req) async {
      switch (req.url.path) {
        case '/api/randonneuring/results':
          return _json({
            'career': '...',
            'items': [
              _result(1, '2026-03-07', 203),
              _result(2, '2026-04-04', 305),
              _result(3, '2026-07-30', 209, type: 'PERMANENT', pt: 'PT-171'),
            ],
          });
        case '/api/brevet/schedule':
          return _json([
            {
              'date': '03.07',
              'region': '서울',
              'name': '200 (서)',
              'distance': '200',
              'hasLink': true,
            },
          ]);
        case '/api/permanents':
          permanentsCalled++;
          return _json([
            {
              'permanentNo': 'PT-171',
              'name': '서해로',
              'distanceKm': 209,
              'timeLimitHm': '13:58',
              'gpxLabel': 'PT-171',
              'polyline': '_p~iF~ps|U_ulLnnqC',
            },
            {
              'permanentNo': 'PT-01',
              'name': '글레터페스트',
              'distanceKm': 202,
              'timeLimitHm': '13:28',
            },
          ]);
      }
      return http.Response('not found', 404);
    });

    await _pump(
      tester,
      RandonneuringScreen(
        api: RandonneuringApi(client: client),
        now: DateTime(2026, 11, 25),
      ),
    );
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.text('2026 슈퍼 랜도너 시리즈 (브레베 완주)'), findsOneWidget);
    // 퍼머넌트 탭을 열기 전에는 큰 코스 목록을 받지 않음
    expect(permanentsCalled, 0);

    await tester.tap(find.text('퍼머넌트'));
    await tester.pumpAndSettle();
    expect(permanentsCalled, 1);
    expect(find.text('완주 1 / 2 코스'), findsOneWidget);
    expect(find.text('PT-171 서해로'), findsOneWidget);

    await tester.tap(find.text('안 가본 코스만'));
    await tester.pumpAndSettle();
    expect(find.text('PT-171 서해로'), findsNothing);
    expect(find.text('PT-01 글레터페스트'), findsOneWidget);
  });
}
