import 'package:http/http.dart' as http;

import '../models/randonneuring.dart';
import 'api_client.dart';

// 랜도너스: 내 공식 기록(/api/randonneuring/results) · 협회 일정(/api/brevet/schedule)
// · 퍼머넌트 코스(/api/permanents). 조회는 모두 공개
class RandonneuringApi {
  RandonneuringApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  // 최신순
  Future<List<RandoResult>> fetchResults() async {
    final body = await getJson(_client, '/api/randonneuring/results') as Map;
    final items = (body['items'] as List? ?? const [])
        .map((e) => RandoResult.fromJson(e as Map<String, dynamic>))
        .toList();
    return items..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<List<BrevetEvent>> fetchSchedule() async {
    final list = await getJson(_client, '/api/brevet/schedule') as List;
    return [
      for (final e in list) BrevetEvent.fromJson(e as Map<String, dynamic>),
    ];
  }

  // 코스마다 경로(polyline)가 들어 있어 응답이 큼(수 MB). 화면에서 한 번만 받아 둠
  Future<List<PermanentCourse>> fetchPermanents() async {
    final list = await getJson(_client, '/api/permanents') as List;
    return [
      for (final e in list) PermanentCourse.fromJson(e as Map<String, dynamic>),
    ];
  }
}
