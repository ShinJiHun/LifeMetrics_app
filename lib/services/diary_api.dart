import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'health_sync_service.dart' show healthSyncToken;

// 인간 페르소나 하루 일기 (서버 블로그의 인간 › 일기 › 26년 메뉴에 날짜당 1글)
class Diary {
  const Diary({
    required this.date,
    required this.body,
    this.title,
    this.isPublic = false,
    this.updatedAt,
  });

  final DateTime date;
  final String? title;
  final String body;
  final bool isPublic;
  final DateTime? updatedAt;

  factory Diary.fromJson(Map<String, Object?> j) => Diary(
    date: DateTime.parse(j['date'] as String),
    title: j['title'] as String?,
    body: (j['body'] as String?) ?? '',
    isPublic: j['visibility'] == 'public',
    updatedAt: j['updatedAt'] == null
        ? null
        : DateTime.tryParse(j['updatedAt'] as String),
  );
}

// 일기는 비공개가 기본이라 읽을 때도 헬스 동기화와 같은 앱 토큰으로 인증
class DiaryApi {
  DiaryApi({http.Client? client, String? token})
    : _client = client ?? http.Client(),
      _token = token ?? healthSyncToken;

  final http.Client _client;
  final String _token;

  static String dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // 그날 일기. 없으면 null
  Future<Diary?> fetch(DateTime day) async {
    final res = await _send(
      () => _client.get(_uri(day), headers: _headers),
    );
    if (res.statusCode == 404) return null;
    return Diary.fromJson(_decode(res));
  }

  // 없으면 만들고 있으면 고침. 제목이 비면 서버가 "11월 18일 (수)" 로 붙임
  Future<Diary> save(
    DateTime day, {
    required String body,
    String? title,
    bool isPublic = false,
  }) async {
    final res = await _send(
      () => _client.put(
        _uri(day),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': title,
          'body': body,
          'visibility': isPublic ? 'public' : 'private',
        }),
      ),
    );
    return Diary.fromJson(_decode(res));
  }

  Future<void> delete(DateTime day) async {
    final res = await _send(
      () => _client.delete(_uri(day), headers: _headers),
    );
    if (res.statusCode == 404) return; // 이미 없음
    _decode(res);
  }

  Uri _uri(DateTime day) => Uri.parse('$apiBaseUrl/api/diary/${dateKey(day)}');

  Map<String, String> get _headers => {'Authorization': 'Bearer $_token'};

  Future<http.Response> _send(Future<http.Response> Function() call) async {
    if (_token.isEmpty) {
      throw const ApiException('앱에 토큰(HEALTH_SYNC_TOKEN)이 없어요');
    }
    try {
      return await call().timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const ApiException('서버에 연결할 수 없어요');
    }
  }

  Map<String, Object?> _decode(http.Response res) {
    final text = utf8.decode(res.bodyBytes);
    Map<String, Object?> body;
    try {
      body = text.trim().isEmpty
          ? const {}
          : (jsonDecode(text) as Map).cast<String, Object?>();
    } on FormatException {
      body = const {};
    }
    if (res.statusCode == 401) {
      throw const ApiException('서버가 앱 토큰을 받지 않았어요');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(
        (body['message'] as String?) ?? '서버 오류가 났어요 (${res.statusCode})',
      );
    }
    return body;
  }
}
