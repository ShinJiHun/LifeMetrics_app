import 'dart:convert';

import 'package:http/http.dart' as http;

// lifemetrics 백엔드 주소. --dart-define=API_BASE_URL=... 로 바꿀 수 있음
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://34.172.162.148:8081',
);

// 서버에 로그인이 없어 기본 사용자(1)로 조회
const apiUserId = 1;

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
String? _adminCookie;

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
    res = await client.get(uri).timeout(const Duration(seconds: 10));
  } catch (_) {
    throw const ApiException('서버에 연결할 수 없어요');
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

// 관리자 전용 API 응답 처리. 403 ADMIN_REQUIRED 는 로그인부터 하도록 따로 구분
Object? _decodeAdminResponse(http.Response res) {
  if (res.statusCode == 403 && res.body.contains('ADMIN_REQUIRED')) {
    _adminCookie = null; // 세션이 만료됐을 수 있어 다시 로그인하게
    throw const AdminRequiredException();
  }
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw ApiException('서버 오류가 났어요 (${res.statusCode})');
  }
  final text = utf8.decode(res.bodyBytes);
  return text.trim().isEmpty ? null : jsonDecode(text);
}
