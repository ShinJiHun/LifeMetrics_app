import 'package:http/http.dart' as http;

import '../models/ride.dart';
import '../models/ride_detail.dart';
import 'api_client.dart';

// 백엔드 /api/activity
class RideApi {
  RideApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  // 라이딩 목록, 최신순
  Future<List<Ride>> fetchRides() async {
    final list = await getJson(_client, '/api/activity/list') as List;
    final rides = list
        .map((e) => Ride.fromJson(e as Map<String, dynamic>))
        .toList();
    return rides..sort((a, b) => b.startTime.compareTo(a.startTime));
  }

  Future<RideDetail> fetchDetail(int id) async => RideDetail.fromJson(
    await getJson(_client, '/api/activity/$id/summary') as Map<String, dynamic>,
  );

  // 지나간 구간 기록, 지나간 순서대로
  Future<List<RideSegment>> fetchSegments(int id) async {
    final list = await getJson(_client, '/api/activity/$id/segments') as List;
    return list
        .map((e) => RideSegment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // AI 분석. 아직 분석하지 않은 라이딩이면 서버가 빈 본문(200)을 주므로 null
  Future<RideAnalysis?> fetchAnalysis(int id) async {
    final Object? body;
    try {
      body = await getJson(_client, '/api/ai/analysis/activity/$id');
    } on ApiException {
      return null;
    } on FormatException {
      return null;
    }
    return body is Map<String, dynamic> ? RideAnalysis.fromJson(body) : null;
  }
}
