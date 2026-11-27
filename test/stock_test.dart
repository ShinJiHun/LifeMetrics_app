import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lifemetrics_app/models/stock.dart';
import 'package:lifemetrics_app/screens/investor/stock_screen.dart';
import 'package:lifemetrics_app/services/api_client.dart';
import 'package:lifemetrics_app/services/stock_api.dart';

http.Response _json(Object? body, [int status = 200, Map<String, String>? h]) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8', ...?h},
    );

final _forbidden = _json({'message': '관리자만 접근할 수 있습니다.'}, 403);

Map<String, Object?> _snap(String at, double rate) => {
  'id': 1,
  'snapshotAt': at,
  'snapshotDate': at.substring(0, 10),
  'session': 'KR_CLOSE',
  'accountSuffix': '1234',
  'purchaseKrw': 1000000,
  'purchaseUsd': 500.5,
  'evalKrw': 1100000,
  'evalUsd': 520.25,
  'pnlKrw': 100000,
  'pnlUsd': 19.75,
  'pnlAfterCostKrw': null,
  'pnlAfterCostUsd': null,
  'pnlRate': rate,
  'pnlRateAfterCost': rate - 0.001,
  'dailyPnlKrw': -5000,
  'dailyPnlUsd': 1.5,
  'dailyPnlRate': -0.002,
  'holdingCount': 2,
};

final _summary = {
  'latest': _snap('2026-11-26T15:40:00', 0.0512),
  'holdings': [
    {
      'market': 'KR',
      'symbol': '005930',
      'name': '삼성전자',
      'currency': 'KRW',
      'quantity': 10,
      'avgPrice': 60000,
      'currentPrice': 66000,
      'purchaseAmount': 600000,
      'evalAmount': 660000,
      'pnl': 60000,
      'pnlRate': 0.1,
      'dailyPnl': -1000,
      'dailyPnlRate': -0.0015,
    },
    {
      'market': 'US',
      'symbol': 'VOO',
      'name': null,
      'currency': 'USD',
      'quantity': 1.25,
      'avgPrice': 400.4,
      'currentPrice': 416.2,
      'purchaseAmount': 500.5,
      'evalAmount': 520.25,
      'pnl': 19.75,
      'pnlRate': 0.0394,
      'dailyPnl': 1.5,
      'dailyPnlRate': 0.0029,
    },
  ],
  'history': [
    _snap('2026-11-26T15:40:00', 0.0512),
    _snap('2026-11-25T15:40:00', 0.031),
    _snap('2026-11-24T15:40:00', -0.012),
  ],
};

const _profit = {
  'firstDate': '2025-03-02',
  'lastDate': '2026-11-26',
  'txCount': 321,
  'flows': [],
  'holdingsKrw': 660000,
  'holdingsUsd': 520.25,
  'holdingsAt': '2026-11-26T15:40:00',
  'usdKrw': 1395.5,
  'usdKrwDate': '2026-11-20',
  'depositKrw': 2000000,
  'withdrawalKrw': 500000,
  'netDepositKrw': 1500000,
  'cashKrw': 200000,
  'holdingsTotalKrw': 1386009,
  'currentAssetKrw': 1586009,
  'totalProfitKrw': 86009,
  'profitRateOnDeposit': 0.0573,
  'incomeKrw': 1200,
  'feeKrw': 3400,
  'unknownTypes': [],
};

Map<String, Object?> _tx(int id, String type, {String? name, bool cancel = false}) => {
  'id': id,
  'accountSuffix': '1234',
  'settlementDate': '2026-11-2$id',
  'settled': true,
  'transactionTime': '2026-11-2${id}T10:00:00',
  'transactionType': type,
  'cancellation': cancel,
  'market': 'KR',
  'currency': 'KRW',
  'assetClass': null,
  'symbol': name == null ? null : '005930',
  'name': name,
  'quantity': name == null ? null : 2,
  'filledPrice': name == null ? null : 65000,
  'amount': 130000,
  'commission': 20,
  'tax': 0,
  'netAmount': 130020,
  'exchangeRate': null,
};

final _txs = [
  _tx(5, 'BUY', name: '삼성전자'),
  _tx(4, 'DEPOSIT'),
  _tx(3, 'DIVIDEND', name: '삼성전자'),
];

http.Response _route(http.Request req) => switch (req.url.path) {
  '/api/stock/summary' => _json(_summary),
  '/api/stock/profit' => _json(_profit),
  '/api/stock/transactions' => _json(_txs),
  _ => _json({'message': 'not found'}, 404),
};

void main() {
  group('모델', () {
    test('요약 · 수익 · 거래를 읽음 (null · 정수 숫자 포함)', () {
      final s = StockSummary.fromJson(_summary);
      expect(s.latest!.evalKrw, 1100000);
      expect(s.latest!.sessionLabel, '국내 마감');
      expect(s.holdings, hasLength(2));
      expect(s.holdings[1].displayName, 'VOO'); // 이름이 없으면 심볼
      expect(s.holdings[1].quantity, 1.25);
      expect(s.history, hasLength(3));

      final p = StockProfit.fromJson(_profit);
      expect(p.totalProfitKrw, 86009);
      expect(p.profitRateOnDeposit, closeTo(0.0573, 1e-9));

      final t = StockTransaction.fromJson(_tx(4, 'DEPOSIT'));
      expect(t.typeLabel, '입금');
      expect(t.title, '입금'); // 종목이 없으면 유형 이름
      expect(t.cashDirection, 1);
      expect(StockTransaction.fromJson(_tx(5, 'BUY')).cashDirection, -1);
    });

    test('스냅샷이 없으면 latest 는 null', () {
      final s = StockSummary.fromJson({'latest': null, 'holdings': [], 'history': []});
      expect(s.latest, isNull);
      expect(s.holdings, isEmpty);
    });
  });

  group('StockApi', () {
    test('로그인 전 403 은 AdminRequiredException, 로그인 뒤 쿠키 · 기간을 실어 보냄', () async {
      var loggedIn = false;
      Uri? txUri;
      final api = StockApi(
        client: MockClient((req) async {
          if (req.url.path == '/api/admin/login') {
            loggedIn = true;
            return _json({'admin': true}, 200, {
              'set-cookie': 'lm_admin=abc; Path=/',
            });
          }
          if (!loggedIn) return _forbidden;
          expect(req.headers['Cookie'], 'lm_admin=abc');
          if (req.url.path == '/api/stock/transactions') txUri = req.url;
          return _route(req);
        }),
      );

      await expectLater(api.summary(), throwsA(isA<AdminRequiredException>()));
      expect(await api.loginAdmin('pw'), isTrue);
      expect((await api.summary()).holdings, hasLength(2));
      final txs = await api.transactions(
        from: DateTime(2026, 8, 28),
        to: DateTime(2026, 11, 26),
        type: 'BUY',
      );
      expect(txs, hasLength(3));
      expect(txUri!.queryParameters, {
        'from': '2026-08-28',
        'to': '2026-11-26',
        'type': 'BUY',
      });
    });
  });

  group('StockScreen', () {
    Future<void> pump(WidgetTester tester, StockApi api) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: const Color(0xFF15122B),
            body: StockScreen(api: api, now: DateTime(2026, 11, 26)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('총 수익 · 계좌 요약 · 보유 종목 · 최근 거래를 보여주고 필터로 거름', (tester) async {
      // 화면을 길게 해서 아래 섹션까지 한 번에 그림
      tester.view.physicalSize = const Size(1080, 6000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await pump(tester, StockApi(client: MockClient((r) async => _route(r))));

      expect(find.text('+86,009원'), findsWidgets);
      expect(find.text('넣은 돈 대비 +5.73%'), findsOneWidget);
      expect(find.text('계좌 요약'), findsOneWidget);
      expect(find.text('+5.12%'), findsOneWidget);
      expect(find.text('수익률 추이'), findsOneWidget);
      expect(find.text('삼성전자'), findsWidgets);
      expect(find.text('VOO'), findsOneWidget);
      expect(find.text('\$520.25'), findsWidgets);

      // 최근 거래: 매수 · 입금 · 배당 세 건
      expect(find.textContaining('매수 · 2주'), findsOneWidget);
      expect(find.text('-130,020원'), findsOneWidget);
      expect(find.text('+130,020원'), findsNWidgets(2));

      await tester.tap(find.text('입출금'));
      await tester.pumpAndSettle();
      expect(find.textContaining('매수 · 2주'), findsNothing);
      expect(find.text('+130,020원'), findsOneWidget);
    });

    testWidgets('로그인을 취소하면 로그인 안내를 보여줌', (tester) async {
      await pump(tester, StockApi(client: MockClient((_) async => _forbidden)));
      // 처음 열 때 비밀번호 창이 뜸 → 취소
      expect(find.text('관리자 로그인'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(find.text('관리자 로그인이 필요해요'), findsOneWidget);
    });

    testWidgets('서버 오류면 다시 시도 버튼', (tester) async {
      await pump(
        tester,
        StockApi(client: MockClient((_) async => _json({'message': 'DB 오류'}, 500))),
      );
      expect(find.text('계좌 정보를 불러오지 못했어요'), findsOneWidget);
      expect(find.text('DB 오류'), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);
    });
  });
}
