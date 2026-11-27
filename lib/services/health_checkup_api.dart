import 'package:http/http.dart' as http;

import '../models/health_checkup.dart';
import 'api_client.dart';

// 서버 건강검진 API (/api/body/health-checkups). 조회도 관리자 전용 →
// 로그인 전이면 AdminRequiredException
class HealthCheckupApi {
  HealthCheckupApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<bool> loginAdmin(String password) => postAdminLogin(_client, password);

  // 최근 검진이 앞에 오도록 날짜 내림차순
  Future<List<HealthCheckup>> fetchAll() async {
    final body = await sendAdminJson(
      _client,
      'GET',
      '/api/body/health-checkups?userId=$apiUserId',
    );
    if (body is! List) throw const ApiException('서버 응답을 읽지 못했어요');
    return [
      for (final e in body) HealthCheckup.fromJson(e as Map<String, dynamic>),
    ]..sort((a, b) => b.date.compareTo(a.date));
  }

  // 검진 결과통보서 PDF → AI 가 수치를 뽑아 돌려줌 (저장 안 함, 관리자).
  // 결과통보서가 3쪽 · 50여 항목이라 AI 가 1~2분 걸릴 수 있어 넉넉히 기다림.
  // 스캔 이미지 PDF 는 서버가 글자를 못 읽어 422 + 이유 메시지
  Future<Map<String, dynamic>> extract(List<int> bytes, String filename) async {
    final body = await postFile(
      _client,
      '/api/body/health-checkups/extract',
      bytes: bytes,
      filename: filename,
      timeout: const Duration(seconds: 150),
    );
    if (body is! Map) throw const ApiException('서버 응답을 읽지 못했어요');
    return body.cast<String, dynamic>();
  }

  // 검토한 검진 저장 (관리자)
  Future<void> create(Map<String, dynamic> checkup) =>
      postJson(_client, '/api/body/health-checkups', checkup);
}
