import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/workout.dart';
import 'api_client.dart';
import 'fitness_api.dart';

// 개발 서버(8081)에만 저장된 운동 기록을 운영으로 옮기기.
// 앱 기본 주소가 개발 서버였던 동안 입력한 기록이 운영 DB 에 없어서 만든 일회성 도구.
// 개발 DB 를 통째로 복사하지 않고, 개발 서버의 기록을 읽어 운영 서버 저장 API 로 다시 보냄
// (운영에서 id 가 새로 매겨지고, 운영에만 있는 기록은 건드리지 않음)
class DevImportService {
  DevImportService({http.Client? client, this.devBase = devBaseUrl})
    : _client = client ?? http.Client(),
      _prod = FitnessApi(client: client);

  final http.Client _client;
  final FitnessApi _prod;
  final String devBase;

  Future<bool> loginAdmin(String password) => _prod.loginAdmin(password);

  // 개발 서버에는 있는데 운영에는 없는 운동 기록 (최신순).
  // 서버는 같은 날짜 세션에 기록을 이어 붙이므로 세션 단위가 아니라 운동(로그) 단위로 비교:
  // 같은 날짜에 같은 종목 · 같은 세트(유산소는 시간 · 칼로리 · 거리)가 운영에 있으면 옮긴 것으로 봄.
  // 돌려주는 세션에는 운영에 없는 운동만 남김 → 여러 번 눌러도 같은 기록이 두 번 가지 않음.
  // '다시 안 보기'로 뺀 운동(ignored)은 목록에 넣지 않음
  Future<List<DevMissing>> findMissing(
    List<DateTime> months, {
    Set<String> ignored = const {},
  }) async {
    final missing = <DevMissing>[];
    for (final m in months) {
      final dev = await _fetchDev(m);
      final prod = await _prod.fetchHistory(m);
      final prodDays = {for (final s in prod) _day(s.date)};
      // 날짜별 운영 운동 서명 개수 (같은 운동을 두 번 했으면 2)
      final have = <String, int>{};
      for (final s in prod) {
        for (final e in s.exercises) {
          final k = keyOf(s.date, e);
          have[k] = (have[k] ?? 0) + 1;
        }
      }
      for (final s in dev) {
        final left = <WorkoutExercise>[];
        for (final e in s.exercises) {
          final k = keyOf(s.date, e);
          final n = have[k] ?? 0;
          if (n > 0) {
            have[k] = n - 1;
          } else if (!ignored.contains(k)) {
            left.add(e);
          }
        }
        if (left.isNotEmpty) {
          missing.add(
            DevMissing(
              s.withExercises(left),
              // 운영에 그날 기록이 이미 있으면 '일부만 다름' → 개발 중 넣은 테스트일 가능성이 큼
              partial: prodDays.contains(_day(s.date)),
            ),
          );
        }
      }
    }
    return missing..sort((a, b) => b.session.date.compareTo(a.session.date));
  }

  // '다시 안 보기': 이 세션의 운동들을 폰에 기억해 두고 다음부터 목록에서 뺌
  static const _ignoredKey = 'dev_import_ignored';

  static Future<Set<String>> loadIgnored() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_ignoredKey) ?? const []).toSet();
  }

  static Future<void> ignore(WorkoutSession s) async {
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(_ignoredKey) ?? const <String>[]).toSet()
      ..addAll([for (final e in s.exercises) keyOf(s.date, e)]);
    await prefs.setStringList(_ignoredKey, set.toList());
  }

  static String _day(DateTime d) => '${d.year}-${d.month}-${d.day}';

  // 운영 서버에 그대로 다시 저장 (관리자). 로그인 전이면 AdminRequiredException
  Future<void> copyToProd(WorkoutSession s) => postJson(
    _client,
    '/api/exercise/log',
    {
      'sessionDate':
          '${s.date.year}-${s.date.month.toString().padLeft(2, '0')}-'
          '${s.date.day.toString().padLeft(2, '0')}',
      'userId': apiUserId,
      'isPT': s.isPT,
      'exercises': [for (final e in s.exercises) e.toLogJson()],
    },
  );

  // 날짜 + 운동 하나의 서명
  static String keyOf(DateTime d, WorkoutExercise e) {
    final sets = [
      for (final s in e.sets) '${s.setNumber}:${s.weight ?? ''}x${s.reps ?? ''}',
    ].join(',');
    return '${d.year}-${d.month}-${d.day}|${e.exerciseItemId}|'
        '${e.isCardio ? '${e.durationSec}/${e.kcal}/${e.distanceKm}/${e.avgHr}' : sets}';
  }

  Future<List<WorkoutSession>> _fetchDev(DateTime month) async {
    final key = '${month.year}-${month.month.toString().padLeft(2, '0')}';
    final list =
        await _getDev('/api/exercise/history', {
              'month': key,
              'userId': '$apiUserId',
            })
            as List;
    return [
      for (final e in list) WorkoutSession.fromJson(e as Map<String, dynamic>),
    ];
  }

  // 개발 서버 GET. 앱 토큰 + 관리자 쿠키(운영과 같은 비밀번호라 개발 서버에서도 통함)를 실음
  Future<Object?> _getDev(String path, [Map<String, String>? query]) async {
    final uri = Uri.parse('$devBase$path').replace(queryParameters: query);
    final http.Response res;
    try {
      res = await _client
          .get(
            uri,
            headers: {
              if (appToken.isNotEmpty) 'Authorization': 'Bearer $appToken',
              'Cookie': ?adminCookie,
            },
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const ApiException(
        '개발 서버에 연결할 수 없어요 (8081 방화벽을 막았다면 허용된 와이파이에서 해 주세요)',
      );
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const AdminRequiredException();
    }
    if (res.statusCode != 200) {
      throw ApiException('개발 서버 오류 (${res.statusCode})');
    }
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  // ── 일기 ──────────────────────────────────────

  // 개발 서버에만 있는 일기(최근 60일). 운영에 그날 메모 · 일기가 하나도 없는 날만 옮김 대상,
  // 운영에 뭔가 있는 날은 partial 로 표시(겹쳐 쓰지 않도록 기본 체크 해제)
  Future<List<DiaryCandidate>> findMissingDiaries() async {
    final devDays = await _getDev('/api/diary/recent') as List;
    final prodDays = await sendAdminJson(_client, 'GET', '/api/diary/recent');
    final prodDates = {
      for (final d in (prodDays as List? ?? const []))
        if ((d as Map)['notes'] != 0 || d['diary'] != null) '${d['date']}',
    };
    final out = <DiaryCandidate>[];
    for (final d in devDays) {
      final date = '${(d as Map)['date']}';
      final day = await _getDev('/api/diary/$date') as Map;
      final notes = [
        for (final n in (day['notes'] as List? ?? const []))
          (n as Map).cast<String, Object?>(),
      ];
      final diary = (day['diary'] as Map?)?.cast<String, Object?>();
      if (notes.isEmpty && diary == null) continue;
      out.add(
        DiaryCandidate(
          date: date,
          notes: notes,
          title: diary?['title'] as String?,
          content: diary?['content'] as String?,
          published: diary?['status'] == 'published',
          partial: prodDates.contains(date),
        ),
      );
    }
    return out..sort((a, b) => b.date.compareTo(a.date));
  }

  // 운영 서버에 다시 만들기: 메모 → (일기가 있었으면) 초안 만들기 → 개발 서버 최종본으로 덮어쓰기
  // → (게시했었으면) 게시. 서버에 '초안 없이 일기 만들기'가 없어 AI 초안을 한 번 거침
  Future<void> copyDiary(DiaryCandidate c, {required bool private}) async {
    for (final n in c.notes) {
      await sendAdminJson(_client, 'POST', '/api/diary/${c.date}/notes', body: {
        'source': n['source'],
        'fileName': n['fileName'],
        'content': n['content'],
      });
    }
    if (c.content == null) return;
    final day = await sendAdminJson(
      _client,
      'POST',
      '/api/diary/${c.date}/generate',
      timeout: const Duration(seconds: 120),
    ) as Map;
    final id = ((day['diary'] as Map?)?['id'] as num?)?.toInt();
    if (id == null) throw const ApiException('운영 서버에서 일기 초안을 만들지 못했어요');
    await sendAdminJson(_client, 'PUT', '/api/diary/entries/$id', body: {
      'title': c.title,
      'content': c.content,
    });
    if (c.published) {
      await sendAdminJson(_client, 'POST', '/api/diary/entries/$id/publish', body: {
        'subId': null,
        'visibility': private ? 'private' : 'public',
      });
    }
  }

// 옮길 후보 세션. partial 이면 운영에 그날 기록이 이미 있고 일부만 다름
class DevMissing {
  const DevMissing(this.session, {required this.partial});

  final WorkoutSession session;
  final bool partial;
}

// 옮길 후보 일기 하루치 (개발 서버 기준)
class DiaryCandidate {
  const DiaryCandidate({
    required this.date,
    required this.notes,
    required this.published,
    required this.partial,
    this.title,
    this.content,
  });

  final String date; // 2026-11-24
  final List<Map<String, Object?>> notes;
  final String? title;
  final String? content; // null 이면 메모만 있고 일기는 없음
  final bool published;
  final bool partial; // 운영에 그날 메모 · 일기가 이미 있음

  String get summary => [
    '메모 ${notes.length}개',
    if (content != null) published ? '게시한 일기' : '일기 초안',
    if (title case final t? when t.trim().isNotEmpty) '「${t.trim()}」',
  ].join(' · ');
}
