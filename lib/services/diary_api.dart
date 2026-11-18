import 'package:http/http.dart' as http;

import '../models/diary.dart';
import 'api_client.dart';

// 서버 인간 일기 API. 전부 관리자 전용 → 로그인 전이면 AdminRequiredException
class DiaryApi {
  DiaryApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static String dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<bool> loginAdmin(String password) => postAdminLogin(_client, password);

  Future<DiaryDay> fetchDay(DateTime day) async =>
      DiaryDay.fromJson(await _map('GET', '/api/diary/${dateKey(day)}'));

  // Claude 앱 대화를 붙여넣으면 app, 직접 쓰면 manual
  Future<DiaryNote> addNote(
    DateTime day,
    String content, {
    String source = 'app',
  }) async => DiaryNote.fromJson(
    await _map(
      'POST',
      '/api/diary/${dateKey(day)}/notes',
      body: {'source': source, 'content': content},
    ),
  );

  Future<void> deleteNote(int id) =>
      sendAdminJson(_client, 'DELETE', '/api/diary/notes/$id');

  // 초안 만들기 · 다시 만들기. 서버가 AI 로 쓰느라 오래 걸림. 고친 초안도 덮어씀
  Future<DiaryDay> generate(DateTime day) async => DiaryDay.fromJson(
    await _map(
      'POST',
      '/api/diary/${dateKey(day)}/generate',
      timeout: const Duration(seconds: 120),
    ),
  );

  Future<DiaryEntry> updateEntry(int id, String title, String content) async =>
      DiaryEntry.fromJson(
        await _map(
          'PUT',
          '/api/diary/entries/$id',
          body: {'title': title, 'content': content},
        ),
      );

  Future<void> discardEntry(int id) =>
      sendAdminJson(_client, 'DELETE', '/api/diary/entries/$id');

  Future<DiarySubMenus> subMenus() async =>
      DiarySubMenus.fromJson(await _map('GET', '/api/diary/sub-menus'));

  Future<DiaryEntry> publish(
    int id, {
    int? subId,
    bool isPublic = false,
  }) async => DiaryEntry.fromJson(
    await _map(
      'POST',
      '/api/diary/entries/$id/publish',
      body: {'subId': subId, 'visibility': isPublic ? 'public' : 'private'},
    ),
  );

  Future<Map<String, Object?>> _map(
    String method,
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final r = await sendAdminJson(
      _client,
      method,
      path,
      body: body,
      timeout: timeout,
    );
    if (r is! Map) throw const ApiException('서버 응답을 읽지 못했어요');
    return r.cast<String, Object?>();
  }
}
