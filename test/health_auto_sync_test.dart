import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lifemetrics_app/models/health_sync.dart';
import 'package:lifemetrics_app/services/api_client.dart';
import 'package:lifemetrics_app/services/health_auto_sync.dart';
import 'package:lifemetrics_app/services/health_service.dart';
import 'package:lifemetrics_app/services/health_sync_service.dart';

class _FakeHealth extends HealthService {
  _FakeHealth({this.background = true, this.sync = true, this.empty = false});

  final bool background;
  final bool sync;
  final bool empty;
  int reads = 0;

  @override
  Future<bool> hasBackgroundPermission() async => background;

  @override
  Future<bool> hasSyncPermissions() async => sync;

  @override
  Future<String?> newChangesToken() async => 'fresh';

  @override
  Future<HealthChanges?> changesSince(String token) async =>
      (deletedIds: const ['gone'], changedIds: null, nextToken: 'next');

  @override
  Future<HealthSyncPayload> collectForSync({
    int dayCount = 7,
    DateTime? now,
  }) async {
    reads++;
    return HealthSyncPayload(
      device: 'android',
      days: [SyncDay(date: DateTime(2026, 11, 1), steps: empty ? 0 : 1000)],
      nutrition: const [],
      exercises: const [],
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  var posts = 0;
  setUp(() => posts = 0);

  http.Client server(int status) => MockClient((_) async {
    posts++;
    return http.Response(
      '{"days":1,"nutrition":0,"exercises":0,"deleted":0}',
      status,
    );
  });

  Future<bool> run(
    _FakeHealth health, {
    http.Client? client,
    String token = 't',
  }) => runHealthAutoSync(
    health: health,
    sync: HealthSyncService(
      health: health,
      client: client ?? server(200),
      token: token,
    ),
  );

  test('성공하면 끝내고 마지막 시각을 남김', () async {
    final health = _FakeHealth();
    expect(await run(health), isTrue);
    expect(posts, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('health_sync_last_at'), isNotNull);
  });

  test('연결 실패와 서버 오류는 재시도', () async {
    expect(await run(_FakeHealth(), client: server(500)), isFalse);
    expect(await run(_FakeHealth(), client: server(503)), isFalse);
    expect(
      await run(
        _FakeHealth(),
        client: MockClient((_) => throw http.ClientException('끊김')),
      ),
      isFalse,
    );
  });

  test('토큰 거부와 잘못된 형식은 재시도하지 않음', () async {
    expect(await run(_FakeHealth(), client: server(401)), isTrue);
    expect(await run(_FakeHealth(), client: server(400)), isTrue);
  });

  test('권한이나 토큰이 없으면 읽지도 보내지도 않고 재시도도 안 함', () async {
    for (final (health, token) in [
      (_FakeHealth(background: false), 't'),
      (_FakeHealth(sync: false), 't'),
      (_FakeHealth(), ''),
    ]) {
      expect(await run(health, token: token), isTrue);
      expect(health.reads, 0);
    }
    expect(posts, 0);
  });

  test('읽은 값이 통째로 비면 서버를 덮어쓰지 않고 재시도', () async {
    SharedPreferences.setMockInitialValues({
      'health_sync_changes_token': 'old',
      'health_sync_last_at': '2026-10-31T21:00:00.000',
    });
    expect(await run(_FakeHealth(empty: true)), isFalse);
    expect(posts, 0);
    // 삭제 목록을 다음 번에 다시 보낼 수 있도록 토큰과 시각은 그대로
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('health_sync_changes_token'), 'old');
    expect(prefs.getString('health_sync_last_at'), '2026-10-31T21:00:00.000');
  });

  test('수동 동기화도 빈 묶음은 오류로 알림', () {
    final health = _FakeHealth(empty: true);
    expect(
      HealthSyncService(health: health, client: server(200), token: 't').sync(),
      throwsA(isA<ApiException>()),
    );
  });

  group('delayUntilNextKstMidnight', () {
    test('KST 21:25 이면 2시간 35분 뒤', () {
      // 2026-11-07 21:25 KST = 12:25 UTC
      expect(
        delayUntilNextKstMidnight(DateTime.utc(2026, 11, 7, 12, 25)),
        const Duration(hours: 2, minutes: 35),
      );
    });

    test('KST 00:00 정각이면 하루 뒤', () {
      expect(
        delayUntilNextKstMidnight(DateTime.utc(2026, 11, 6, 15)),
        const Duration(days: 1),
      );
    });

    test('UTC 날짜가 하루 앞서 있어도 KST 기준으로 계산', () {
      // 2026-11-30 23:00 UTC = 12-01 08:00 KST → 12-02 00:00 KST 까지 16시간
      expect(
        delayUntilNextKstMidnight(DateTime.utc(2026, 11, 30, 23)),
        const Duration(hours: 16),
      );
    });
  });
}
