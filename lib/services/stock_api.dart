import 'package:http/http.dart' as http;

import '../models/stock.dart';
import 'api_client.dart';

// 서버 증권 API (/api/stock). 개인 금융 정보라 읽기도 관리자 전용 → 로그인 전이면 AdminRequiredException
class StockApi {
  StockApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static String dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<bool> loginAdmin(String password) => postAdminLogin(_client, password);

  Future<StockSummary> summary() async =>
      StockSummary.fromJson(await _map('/api/stock/summary'));

  Future<StockProfit> profit() async =>
      StockProfit.fromJson(await _map('/api/stock/profit'));

  // 기간 거래내역 (정산일 기준, 최신순). type 을 주면 그 유형만
  Future<List<StockTransaction>> transactions({
    DateTime? from,
    DateTime? to,
    String? type,
  }) async {
    final q = {
      if (from != null) 'from': dateKey(from),
      if (to != null) 'to': dateKey(to),
      if (type != null && type.isNotEmpty) 'type': type,
    };
    final path = Uri(
      path: '/api/stock/transactions',
      queryParameters: q.isEmpty ? null : q,
    );
    final r = await sendAdminJson(_client, 'GET', path.toString());
    if (r is! List) throw const ApiException('거래내역 응답 형식이 달라요');
    return r
        .whereType<Map<String, Object?>>()
        .map(StockTransaction.fromJson)
        .toList();
  }

  Future<Map<String, Object?>> _map(String path) async {
    final r = await sendAdminJson(_client, 'GET', path);
    if (r is! Map<String, Object?>) {
      throw const ApiException('서버 응답 형식이 달라요');
    }
    return r;
  }
}
