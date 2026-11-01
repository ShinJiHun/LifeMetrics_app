import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lifemetrics_app/models/health_sync.dart';
import 'package:lifemetrics_app/services/api_client.dart';
import 'package:lifemetrics_app/services/health_service.dart';
import 'package:lifemetrics_app/services/health_sync_service.dart';

// 헬스 커넥트 대신 정해진 묶음과 변경 토큰을 돌려줌
class _FakeHealth extends HealthService {
  _FakeHealth({this.deleted});

  final ({List<String> ids, String nextToken})? deleted;
  int? requestedDays;
  String? askedToken;

  @override
  Future<String?> newChangesToken() async => 'fresh';

  @override
  Future<({List<String> ids, String nextToken})?> deletedSince(
    String token,
  ) async {
    askedToken = token;
    return deleted;
  }

  @override
  Future<HealthSyncPayload> collectForSync({
    int dayCount = 7,
    DateTime? now,
  }) async {
    requestedDays = dayCount;
    return HealthSyncPayload(
      device: 'android',
      days: [SyncDay(date: DateTime(2026, 11, 1), steps: 12345)],
      nutrition: [
        SyncNutrition(
          id: 'n1',
          startTime: DateTime(2026, 11, 1, 8, 5),
          mealType: 'BREAKFAST',
          name: '바나나',
          energyKcal: 93,
        ),
      ],
    );
  }
}

void main() {
  group('형식 변환', () {
    test('시간은 현지 시간 + 오프셋으로 보냄', () {
      final s = isoWithOffset(DateTime(2026, 11, 1, 8, 5, 9));
      final o = DateTime(2026, 11, 1).timeZoneOffset;
      final hh = o.abs().inHours.toString().padLeft(2, '0');
      final mm = (o.abs().inMinutes % 60).toString().padLeft(2, '0');
      expect(s, '2026-11-01T08:05:09${o.isNegative ? '-' : '+'}$hh:$mm');
      expect(isoDate(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('영양소는 g 에서 서버 단위(mg, mcg)로 바꿈', () {
      final n = HealthService.nutritionFromHealth(
        'id-1',
        DateTime(2026, 11, 1, 12),
        NutritionHealthValue(
          name: '김치찌개',
          mealType: 'LUNCH',
          calories: 450,
          protein: 20,
          sodium: 1.8,
          cholesterol: 0.05,
          vitaminA: 0.0003,
          vitaminC: 0.012,
          iron: 0.002,
        ),
        'com.sec.android.app.shealth',
      );
      expect(n.sodiumMg, closeTo(1800, 1e-6));
      expect(n.cholesterolMg, closeTo(50, 1e-6));
      expect(n.vitaminAMcg, closeTo(300, 1e-6));
      expect(n.vitaminCMg, closeTo(12, 1e-6));
      expect(n.ironMg, closeTo(2, 1e-6));
      expect(n.proteinG, 20);
      expect(n.toJson()['mealType'], 'LUNCH');
      expect(n.toJson()['potassiumMg'], isNull);
    });
  });

  group('HealthSyncService', () {
    late http.Request? sent;
    MockClient server(int status, Object body) => MockClient((req) async {
      sent = req;
      return http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    setUp(() => sent = null);

    test('처음엔 30일을 보내고, 토큰과 마지막 시각을 저장', () async {
      SharedPreferences.setMockInitialValues({});
      final health = _FakeHealth();
      final sync = HealthSyncService(
        health: health,
        client: server(200, {
          'days': 30,
          'nutrition': 1,
          'exercises': 0,
          'deleted': 0,
        }),
        token: 'secret',
      );

      final r = await sync.sync(now: DateTime(2026, 11, 1, 21));

      expect(health.requestedDays, HealthSyncService.firstSyncDays);
      expect(health.askedToken, isNull);
      expect(r.days, 30);
      expect(r.nutrition, 1);
      expect(sent!.headers['Authorization'], 'Bearer secret');
      expect(sent!.url.path, '/api/health-sync');
      final body = jsonDecode(sent!.body) as Map;
      expect(body['days'][0]['date'], '2026-11-01');
      expect(body['nutrition'][0]['id'], 'n1');
      expect(body['deletedIds'], isEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('health_sync_changes_token'), 'fresh');
      expect(await sync.lastSyncedAt(), DateTime(2026, 11, 1, 21));
    });

    test('다음부터는 7일 + 지워진 레코드 id 를 보내고 토큰을 넘김', () async {
      SharedPreferences.setMockInitialValues({
        'health_sync_changes_token': 'old',
        'health_sync_last_at': '2026-10-31T21:00:00.000',
      });
      final health = _FakeHealth(deleted: (ids: ['gone-1'], nextToken: 'next'));
      final sync = HealthSyncService(
        health: health,
        client: server(200, {
          'days': 7,
          'nutrition': 1,
          'exercises': 0,
          'deleted': 1,
        }),
        token: 'secret',
      );

      final r = await sync.sync();

      expect(health.requestedDays, HealthSyncService.syncDays);
      expect(health.askedToken, 'old');
      expect(r.deleted, 1);
      expect((jsonDecode(sent!.body) as Map)['deletedIds'], ['gone-1']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('health_sync_changes_token'), 'next');
    });

    test('서버가 거절하면 토큰을 넘기지 않아 삭제 목록을 다시 보낼 수 있음', () async {
      SharedPreferences.setMockInitialValues({
        'health_sync_changes_token': 'old',
        'health_sync_last_at': '2026-10-31T21:00:00.000',
      });
      final sync = HealthSyncService(
        health: _FakeHealth(deleted: (ids: ['gone-1'], nextToken: 'next')),
        client: server(401, {'message': 'nope'}),
        token: 'wrong',
      );

      await expectLater(
        sync.sync(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('토큰'),
          ),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('health_sync_changes_token'), 'old');
      expect(prefs.getString('health_sync_last_at'), '2026-10-31T21:00:00.000');
    });

    test('토큰이 없으면 보내지 않음', () async {
      SharedPreferences.setMockInitialValues({});
      final sync = HealthSyncService(
        health: _FakeHealth(),
        client: server(200, {}),
        token: '',
      );
      expect(sync.configured, isFalse);
      await expectLater(sync.sync(), throwsA(isA<ApiException>()));
      expect(sent, isNull);
    });
  });
}
