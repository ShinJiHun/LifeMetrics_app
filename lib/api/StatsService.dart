import 'dart:convert';
import 'package:http/http.dart' as http;

class StatsService {
  static const String baseUrl = 'http://34.172.162.148:8085/api/rides';

  /// 📊 월별 통계 데이터 가져오기
  static Future<List<Map<String, dynamic>>> fetchMonthlyStats() async {
    final res = await http.get(Uri.parse('$baseUrl/stats/monthly'));
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to load stats');
    }
  }

  static Future<List<Map<String, dynamic>>> fetchWeeklyStats({int weeks = 12}) async {
    final uri = Uri.parse("$baseUrl/stats/weekly?weeks=$weeks");
    final res = await http.get(uri);

    if (res.statusCode == 200) {
      return List<Map<String, dynamic>>.from(json.decode(res.body));
    } else {
      throw Exception("Failed to load weekly stats: ${res.statusCode}");
    }
  }

  static Future<Map<String, dynamic>> fetchLatestSummary() async {
    final uri = Uri.parse("$baseUrl/stats/latest-summary");
    final res = await http.get(uri);

    if (res.statusCode == 200) {
      return json.decode(res.body) as Map<String, dynamic>;
    } else {
      throw Exception("Failed to fetch latest summary: ${res.statusCode}");
    }
  }
}
