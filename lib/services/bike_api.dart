import 'package:http/http.dart' as http;

import '../models/bike.dart';
import 'api_client.dart';

// 백엔드 /api/bikes (BikeController, BikeFitController). 조회는 공개
class BikeApi {
  BikeApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  // 서버 정렬 그대로: 쓰는 자전거 먼저, 기본 자전거 먼저
  Future<List<Bike>> fetchBikes() async {
    final list = await getJson(_client, '/api/bikes') as List;
    return [for (final e in list) Bike.fromJson(e as Map<String, dynamic>)];
  }

  Future<List<GearUsage>> fetchGearUsage(int bikeId) async {
    final list = await getJson(_client, '/api/bikes/$bikeId/gear-usage') as List;
    return [for (final e in list) GearUsage.fromJson(e as Map<String, dynamic>)];
  }

  Future<bool> loginAdmin(String password) => postAdminLogin(_client, password);

  // 피팅 저장 (관리자). 로그인 전이면 AdminRequiredException
  Future<void> createFit(int bikeId, Map<String, Object?> fit) =>
      postJson(_client, '/api/bikes/$bikeId/fits', fit);

  Future<List<BikeFit>> fetchFits(int bikeId) async {
    final list = await getJson(_client, '/api/bikes/$bikeId/fits') as List;
    return [for (final e in list) BikeFit.fromJson(e as Map<String, dynamic>)];
  }
}
