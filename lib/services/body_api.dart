import 'package:http/http.dart' as http;

import '../models/body_record.dart';
import 'api_client.dart';

// 백엔드 /api/body
class BodyApi {
  BodyApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  // 전체 신체 기록, 날짜 오름차순
  Future<List<BodyRecord>> fetchRecords() async {
    final body = await getJson(_client, '/api/body/records') as Map;
    final list = (body['records'] as List? ?? const [])
        .map((e) => BodyRecord.fromJson(e as Map<String, dynamic>))
        .toList();
    return list..sort((a, b) => a.date.compareTo(b.date));
  }

  // 관리자 로그인. 업로드는 관리자만 할 수 있음
  Future<bool> loginAdmin(String password) => postAdminLogin(_client, password);

  // 인바디 기록지 사진 업로드. 서버가 사진을 AI 로 읽어 비동기로 저장하므로
  // 성공해도 기록은 몇 초 뒤에 생김
  Future<void> uploadInbody(List<int> bytes, String filename) async {
    final body = await postFile(
      _client,
      '/api/body/inbody/upload',
      bytes: bytes,
      filename: filename,
      fields: const {'type': 'INBODY'},
    ) as Map;
    if (body['success'] != true) {
      throw ApiException('업로드에 실패했어요: ${body['message'] ?? '알 수 없는 오류'}');
    }
  }
}
