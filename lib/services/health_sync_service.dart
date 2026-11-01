import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/health_sync.dart';
import 'api_client.dart';
import 'health_service.dart';

// 서버의 HEALTH_SYNC_TOKEN 과 같은 값. env.json 에 넣고 --dart-define-from-file=env.json 으로 빌드
const healthSyncToken = String.fromEnvironment('HEALTH_SYNC_TOKEN');

// 헬스 커넥트에서 읽은 활동량 · 식단 · 운동을 서버(POST /api/health-sync)로 올림.
// 같은 레코드를 다시 보내도 서버가 레코드 id 로 덮어쓰므로 최근 며칠을 통째로 다시 보냄
class HealthSyncService {
  HealthSyncService({
    HealthService? health,
    http.Client? client,
    this.token = healthSyncToken,
  }) : _health = health ?? HealthService(),
       _client = client ?? http.Client();

  final HealthService _health;
  final http.Client _client;
  final String token;

  static const _changesTokenKey = 'health_sync_changes_token';
  static const _lastSyncKey = 'health_sync_last_at';

  // 처음엔 한 달을 채우고, 그 뒤엔 늦게 들어온 기록까지 덮도록 일주일씩
  static const firstSyncDays = 30;
  static const syncDays = 7;

  bool get configured => token.isNotEmpty;

  // 이 폰에서 마지막으로 동기화에 성공한 시각
  Future<DateTime?> lastSyncedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_lastSyncKey);
    return s == null ? null : DateTime.tryParse(s);
  }

  Future<HealthSyncResult> sync({DateTime? now}) async {
    if (!configured) {
      throw const ApiException('앱에 동기화 토큰(HEALTH_SYNC_TOKEN)이 없어요');
    }
    final prefs = await SharedPreferences.getInstance();

    // 데이터를 읽기 전에 토큰부터 잡아야 읽는 사이에 지워진 기록도 다음 번에 잡힘
    final saved = prefs.getString(_changesTokenKey);
    final changes = saved == null ? null : await _health.deletedSince(saved);
    final nextToken = changes?.nextToken ?? await _health.newChangesToken();

    final first = prefs.getString(_lastSyncKey) == null;
    final payload = (await _health.collectForSync(
      dayCount: first ? firstSyncDays : syncDays,
      now: now,
    )).withDeleted(changes?.ids ?? const []);

    final result = await _post(payload);

    // 서버 반영이 끝난 뒤에만 토큰을 넘겨야 실패 시 삭제 목록을 다시 보낼 수 있음
    if (nextToken != null) await prefs.setString(_changesTokenKey, nextToken);
    await prefs.setString(
      _lastSyncKey,
      (now ?? DateTime.now()).toIso8601String(),
    );
    return result;
  }

  Future<HealthSyncResult> _post(HealthSyncPayload payload) async {
    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('$apiBaseUrl/api/health-sync'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(payload.toJson()),
          )
          .timeout(const Duration(seconds: 60));
    } catch (_) {
      throw const ApiException('서버에 연결할 수 없어요');
    }

    final text = utf8.decode(res.bodyBytes);
    Map<String, Object?> body() {
      try {
        return (jsonDecode(text) as Map).cast<String, Object?>();
      } catch (_) {
        return const {};
      }
    }

    return switch (res.statusCode) {
      200 => HealthSyncResult.fromJson(body()),
      401 => throw const ApiException('동기화 토큰이 서버와 맞지 않아요'),
      503 => throw const ApiException('서버에 동기화 토큰이 설정되지 않았어요'),
      400 => throw ApiException(
        body()['message'] as String? ?? '보낸 데이터 형식이 맞지 않아요',
      ),
      final code => throw ApiException('서버 오류가 났어요 ($code)'),
    };
  }
}
