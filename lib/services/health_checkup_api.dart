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
}
