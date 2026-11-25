import 'dart:convert';

import 'package:http/http.dart' as http;

// lifemetrics 백엔드 주소. --dart-define=API_BASE_URL=... 로 바꿀 수 있음
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://34.172.162.148:8081',
);

// 서버에 로그인이 없어 기본 사용자(1)로 조회
const apiUserId = 1;

// 앱 전용 토큰(서버 .env 의 HEALTH_SYNC_TOKEN). env.json → --dart-define-from-file 로 넣음.
// 지금 서버는 GET 을 누구에게나 열어 두지만, 읽기도 막도록 바뀌면 앱은 이 토큰으로 읽음.
// 비어 있으면 헤더를 보내지 않음
const appToken = String.fromEnvironment('HEALTH_SYNC_TOKEN');

// 읽기 요청 공통 헤더: 앱 토큰 + (로그인했다면) 관리자 쿠키
Map<String, String> _readHeaders() => {
  if (appToken.isNotEmpty) 'Authorization': 'Bearer $appToken',
  'Cookie': ?_adminCookie,
};

// 서버가 주는 상대 경로(/api/exercise/gif/...)를 전체 URL 로. 이미 http 로 시작하면 그대로
String apiUrl(String path) =>
    path.startsWith('http') ? path : '$apiBaseUrl$path';

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

// 서버가 관리자 로그인을 요구할 때(403 ADMIN_REQUIRED)
class AdminRequiredException extends ApiException {
  const AdminRequiredException() : super('관리자 로그인이 필요해요');
}

// 관리자 로그인으로 받은 세션 쿠키. 앱이 켜져 있는 동안만 기억
// (지문 로그인을 켜면 AdminBiometric 이 폰 보안 저장소에 따로 보관했다가 다시 넣어 줌)
String? _adminCookie;

// 지금 들고 있는 관리자 쿠키 (지문 로그인용으로 저장할 때)
String? get adminCookie => _adminCookie;

// 저장해 둔 관리자 쿠키를 다시 씀 (지문 인증 성공 후)
void restoreAdminCookie(String cookie) => _adminCookie = cookie;

// 들고 있던 관리자 쿠키를 서버가 거절했을 때(만료 · 비밀번호 변경) 알림.
// AdminBiometric 이 저장해 둔 쿠키를 지우는 데 씀
void Function()? onAdminCookieRejected;

// 관리자 비밀번호로 로그인. 틀리면 false
Future<bool> postAdminLogin(http.Client client, String password) async {
  final http.Response res;
  try {
    res = await client
        .post(
          Uri.parse('$apiBaseUrl/api/admin/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'password': password}),
        )
        .timeout(const Duration(seconds: 10));
  } catch (_) {
    throw const ApiException('서버에 연결할 수 없어요');
  }
  if (res.statusCode == 401) return false;
  if (res.statusCode != 200) {
    throw ApiException('서버 오류가 났어요 (${res.statusCode})');
  }
  final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
  // Set-Cookie 의 이름=값 부분만 다음 요청에 실어 보냄
  final cookie = res.headers['set-cookie']?.split(';').first;
  if (body['admin'] != true || cookie == null) return false;
  _adminCookie = cookie;
  return true;
}

// GET 후 JSON 디코드. 실패는 화면에 그대로 보여줄 문구의 ApiException 으로
Future<Object?> getJson(
  http.Client client,
  String path, {
  Map<String, String> query = const {},
}) async {
  final uri = Uri.parse('$apiBaseUrl$path')
      .replace(queryParameters: {...query, 'userId': '$apiUserId'});

  final http.Response res;
  try {
    res = await client
        .get(uri, headers: _readHeaders())
        .timeout(const Duration(seconds: 10));
  } catch (_) {
    throw const ApiException('서버에 연결할 수 없어요');
  }
  if (res.statusCode == 401 || res.statusCode == 403) {
    throw ApiException(
      appToken.isEmpty
          ? '서버가 읽기 권한을 요구해요. env.json 에 HEALTH_SYNC_TOKEN 을 넣고 실행해 주세요'
          : '서버가 앱 토큰을 받지 않았어요 (${res.statusCode})',
    );
  }
  if (res.statusCode != 200) {
    throw ApiException('서버 오류가 났어요 (${res.statusCode})');
  }
  return jsonDecode(utf8.decode(res.bodyBytes));
}

// 파일 하나를 multipart(file 필드)로 POST 후 JSON 디코드. 서버가 AI 로 읽느라 오래 걸릴 수 있어 넉넉히 기다림
Future<Object?> postFile(
  http.Client client,
  String path, {
  required List<int> bytes,
  required String filename,
  Map<String, String> fields = const {},
}) async {
  final uri = Uri.parse('$apiBaseUrl$path')
      .replace(queryParameters: {'userId': '$apiUserId'});
  final req = http.MultipartRequest('POST', uri)
    ..headers.addAll({'Cookie': ?_adminCookie})
    ..fields.addAll(fields)
    ..files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );

  final http.Response res;
  try {
    res = await http.Response.fromStream(
      await client.send(req).timeout(const Duration(seconds: 60)),
    );
  } catch (_) {
    throw const ApiException('서버에 연결할 수 없어요');
  }
  return _decodeAdminResponse(res);
}

// JSON 본문을 관리자 쿠키와 함께 POST. 응답 본문이 비어 있으면 null
Future<Object?> postJson(http.Client client, String path, Object? body) async {
  final http.Response res;
  try {
    res = await client
        .post(
          Uri.parse('$apiBaseUrl$path'),
          headers: {
            'Content-Type': 'application/json',
            'Cookie': ?_adminCookie,
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
  } catch (_) {
    throw const ApiException('서버에 연결할 수 없어요');
  }
  return _decodeAdminResponse(res);
}

// 관리자 쿠키를 싣고 아무 메서드(GET · POST · PUT · DELETE)로 JSON 요청.
// 일기 초안처럼 서버가 AI 를 부르는 요청은 timeout 을 길게 줌
Future<Object?> sendAdminJson(
  http.Client client,
  String method,
  String path, {
  Object? body,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final req = http.Request(method, Uri.parse('$apiBaseUrl$path'))
    ..headers.addAll({'Cookie': ?_adminCookie});
  if (body != null) {
    req.headers['Content-Type'] = 'application/json';
    req.body = jsonEncode(body);
  }
  final http.Response res;
  try {
    res = await http.Response.fromStream(
      await client.send(req).timeout(timeout),
    );
  } catch (_) {
    throw const ApiException('서버에 연결할 수 없어요');
  }
  return _decodeAdminResponse(res);
}

// 관리자 전용 API 응답 처리. 403 은 로그인부터 하도록 따로 구분
// (AdminWriteFilter 는 ADMIN_REQUIRED 코드, 컨트롤러가 직접 막으면 '관리자만 ...' 문구,
//  @ResponseStatus(FORBIDDEN) 예외는 스프링 기본 오류 JSON {"status":403,"error":"Forbidden"} — 건강검진)
Object? _decodeAdminResponse(http.Response res) {
  final text = utf8.decode(res.bodyBytes);
  if (res.statusCode == 403 &&
      (text.contains('ADMIN_REQUIRED') ||
          text.contains('관리자만') ||
          text.contains('"error":"Forbidden"'))) {
    if (_adminCookie != null) onAdminCookieRejected?.call();
    _adminCookie = null; // 세션이 만료됐을 수 있어 다시 로그인하게
    throw const AdminRequiredException();
  }
  if (res.statusCode < 200 || res.statusCode >= 300) {
    // 서버가 {"message": "..."} 로 이유를 주면 그대로 보여줌
    String? message;
    try {
      final j = jsonDecode(text);
      if (j is Map && j['message'] is String) message = j['message'] as String;
    } catch (_) {}
    throw ApiException(message ?? '서버 오류가 났어요 (${res.statusCode})');
  }
  if (text.trim().isEmpty) return null;
  // /api/exercise/log 처럼 '저장 완료' 같은 글자만 주는 API 도 있어 JSON 이 아니면 글자 그대로
  try {
    return jsonDecode(text);
  } on FormatException {
    return text;
  }
}
