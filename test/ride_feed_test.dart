import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lifemetrics_app/models/ride.dart';
import 'package:lifemetrics_app/models/ride_detail.dart';
import 'package:lifemetrics_app/screens/athlete/riding/ride_detail_screen.dart';
import 'package:lifemetrics_app/screens/athlete/riding/ride_feed_screen.dart';
import 'package:lifemetrics_app/screens/athlete/riding/ride_route_map.dart';
import 'package:lifemetrics_app/services/ride_api.dart';
import 'package:lifemetrics_app/utils/format.dart';

// Google 문서 예제: (38.5,-120.2) (40.7,-120.95) (43.252,-126.453)
const _polyline = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';

void main() {
  Map<String, dynamic> ride(
    int id,
    String startTime, {
    String? name,
    String? rideType,
  }) => {
    'id': id,
    'name': name,
    'startTime': startTime,
    'totalDistance': 98165.8,
    'movingTime': 20009,
    'totalAscent': 1403.0,
    'avgPower': 98.4,
    'hasPower': true,
    'avgHeartRate': 136.3,
    'calories': 2458,
    'relativeEffort': null,
    'gearContext': {'bikeLabel': 'GTR PRO TE'},
    'rideType': rideType,
    'polyline': _polyline,
  };

  Future<void> pumpFeed(WidgetTester tester, http.Client client) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: RideFeedScreen(api: RideApi(client: client)),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('decodePolyline', () {
    final pts = decodePolyline(_polyline);
    expect(pts.length, 3);
    expect(pts[0].$1, closeTo(38.5, 1e-9));
    expect(pts[0].$2, closeTo(-120.2, 1e-9));
    expect(pts[2].$1, closeTo(43.252, 1e-9));
    expect(pts[2].$2, closeTo(-126.453, 1e-9));
    expect(decodePolyline(''), isEmpty);
    expect(decodePolyline('_p~iF'), isEmpty); // 경도 없이 끊긴 입력
  });

  test('Ride.title: 이름 없으면 출발 시간대', () {
    Ride at(int hour, [String? name]) =>
        Ride(id: 1, startTime: DateTime(2026, 9, 20, hour), name: name);
    expect(at(7).title, '아침 라이딩');
    expect(at(12).title, '점심 라이딩');
    expect(at(16).title, '오후 라이딩');
    expect(at(20).title, '저녁 라이딩');
    expect(at(2).title, '야간 라이딩');
    expect(at(7, '부산 - 포항').title, '부산 - 포항');
    expect(at(7, '  ').title, '아침 라이딩');
  });

  test('parseServerTime: Z 는 한국 벽시계, 오프셋이 있으면 변환', () {
    expect(
      parseServerTime('2026-09-20T07:35:15Z'),
      DateTime(2026, 9, 20, 7, 35, 15),
    );
    expect(
      parseServerTime('2026-09-20T07:35:15+09:00'),
      DateTime.utc(2026, 9, 19, 22, 35, 15).toLocal(),
    );
    expect(
      parseServerTime('2026-09-20T07:35:15'),
      DateTime(2026, 9, 20, 7, 35, 15),
    );
  });

  test('지도 타일: Mapbox 토큰이 있을 때만', () {
    expect(mapTilesFor(''), isNull);

    final mapbox = mapTilesFor('pk.abc')!;
    expect(
      mapbox.url,
      'https://api.mapbox.com/styles/v1/mapbox/dark-v11/tiles/256/'
      '{z}/{x}/{y}{r}?access_token=pk.abc',
    );
    expect(mapbox.attribution, contains('Mapbox'));
  });

  test('format helpers', () {
    expect(formatThousands(1403), '1,403');
    expect(formatThousands(2458000), '2,458,000');
    expect(formatThousands(999), '999');
    expect(formatDuration(20009), '5시간 33분');
    expect(formatDuration(1500), '25분');
    expect(
      formatDateTime(DateTime(2026, 9, 20, 16, 5)),
      '2026년 9월 20일 오후 4:05',
    );
    expect(
      formatDateTime(DateTime(2026, 9, 20, 0, 30)),
      '2026년 9월 20일 오전 12:30',
    );
  });

  testWidgets('피드: 최신순 카드 · 기록 · 경로', (tester) async {
    final client = MockClient((req) async {
      expect(req.url.queryParameters['userId'], '1');
      final body = switch (req.url.path) {
        '/api/activity/list' => [
          ride(1, '2026-08-20T04:54:04Z', name: '부산 - 포항 라이딩'),
          ride(2, '2026-09-20T07:35:15Z', rideType: 'TOURING'),
        ],
        '/api/activity/2/summary' => {
          ...ride(2, '2026-09-20T07:35:15Z', rideType: 'TOURING'),
          'avgSpeed': 17.66,
          'maxPower': 512.0,
        },
        '/api/activity/2/segments' => const [],
        '/api/ai/analysis/activity/2' => null,
        _ => fail('unexpected ${req.url.path}'),
      };
      return http.Response.bytes(
        utf8.encode(body == null ? '' : jsonEncode(body)),
        200,
      );
    });
    await pumpFeed(tester, client);

    final cards = tester.widgetList<RideCard>(find.byType(RideCard)).toList();
    expect(cards.map((c) => c.ride.id), [2, 1]);
    expect(cards.first.ride.route.length, 3);

    expect(find.text('98.17 km'), findsWidgets);
    expect(find.text('1,403 m'), findsWidgets);
    expect(find.text('5시간 33분'), findsWidgets);
    expect(find.text('투어링'), findsOneWidget);
    expect(find.text('GTR PRO TE'), findsWidgets);
    // 서버의 07:35Z 는 한국 아침 시각
    expect(find.text('2026년 9월 20일 오전 7:35'), findsOneWidget);
    expect(find.text('아침 라이딩'), findsOneWidget);
    expect(find.byType(FlutterMap), findsWidgets);

    // 카드(지도 포함)를 누르면 상세. 분석이 없으면(빈 본문) 분석 카드는 없음
    await tester.tap(find.byType(RideRouteMap).first);
    await tester.pumpAndSettle();
    expect(find.byType(RideDetailScreen), findsOneWidget);
    expect(find.text('17.7 km/h'), findsOneWidget);
    expect(find.text('512 W'), findsOneWidget);
    expect(find.text('AI 분석'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('부산 - 포항 라이딩'), 200);
    expect(find.text('부산 - 포항 라이딩'), findsOneWidget);
  });

  test('formatClock', () {
    expect(formatClock(3150), '52:30');
    expect(formatClock(59), '0:59');
    expect(formatClock(3912), '1:05:12');
  });

  test('RideAnalysis: 빈 항목은 빼고 섹션으로', () {
    final a = RideAnalysis.fromJson({
      'summary': '403km 완주',
      'score': 64,
      'pacingAnalysis': 'IF 0.45',
      'weatherImpact': '',
      'highlights': ['장거리 완주', ' '],
      'suggestions': null,
    });
    expect(a.score, 64);
    expect(a.sections, [('페이스', 'IF 0.45')]);
    expect(a.highlights, ['장거리 완주']);
    expect(a.suggestions, isEmpty);
  });

  testWidgets('상세: 기록 · AI 분석 · 구간, 지도 누르면 전체 화면', (tester) async {
    final client = MockClient((req) async {
      final body = switch (req.url.path) {
        '/api/activity/7/summary' => {
          ...ride(
            7,
            '2026-10-03T06:30:00Z',
            name: 'SBS 1000K',
            rideType: 'BREVET',
          ),
          'elapsedTime': 105227,
          'maxHeartRate': 178.0,
          'avgCadence': 54.2,
          'weather': {'temperature': 10.5, 'windSpeed': 0.3},
        },
        '/api/activity/7/segments' => [
          {
            'effortId': 11513,
            'segmentName': '광나루 → 능내역',
            'distance': 22530.2,
            'avgGrade': 0.1,
            'movingTimeSec': 3150,
            'avgPower': 147.2,
            'prRank': 1,
          },
        ],
        '/api/ai/analysis/activity/7' => {
          'summary': '403km 완주, 케이던스 낮음',
          'score': 64,
          'intensityFactor': 0.45,
          'trainingStress': 399,
          'highlights': ['장거리 완주'],
          'suggestions': ['케이던스 80rpm 이상'],
          'recoveryAdvice': '48시간 휴식',
        },
        _ => fail('unexpected ${req.url.path}'),
      };
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: RideDetailScreen(
          ride: Ride.fromJson(
            ride(7, '2026-10-03T06:30:00Z', name: 'SBS 1000K'),
          ),
          api: RideApi(client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SBS 1000K'), findsOneWidget);
    expect(find.text('브레베'), findsOneWidget);
    expect(find.text('29시간 13분'), findsOneWidget); // 경과 시간
    expect(find.text('178 bpm'), findsOneWidget);
    expect(find.text('10.5°C'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('TSS 399'), 300);
    expect(find.text('64 / 100', findRichText: true), findsOneWidget);
    expect(find.text('TSS 399'), findsOneWidget);
    expect(find.text('케이던스 80rpm 이상'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('광나루 → 능내역'), 300);
    expect(find.text('구간 1개'), findsOneWidget);
    expect(find.text('PR'), findsOneWidget);
    expect(find.text('52:30'), findsOneWidget);

    await tester.scrollUntilVisible(find.byType(RideRouteMap), -300);
    await tester.tap(find.byType(RideRouteMap));
    await tester.pumpAndSettle();
    expect(find.byType(RideMapScreen), findsOneWidget);
  });

  testWidgets('피드: 연결 실패 → 다시 시도 → 빈 목록', (tester) async {
    var calls = 0;
    final client = MockClient((_) async {
      if (++calls == 1) throw http.ClientException('down');
      return http.Response('[]', 200);
    });
    await pumpFeed(tester, client);

    expect(find.text('서버에 연결할 수 없어요'), findsOneWidget);
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('아직 라이딩 기록이 없어요'), findsOneWidget);
  });
}
