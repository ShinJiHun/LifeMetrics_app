import 'package:flutter/material.dart';
import '../../api/StatsService.dart';
import 'widgets/WeekSummaryCard.dart';
import 'widgets/StatsChart.dart';
import 'widgets/StatsListSection.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool isLoading = true;

  // ✅ API 데이터 저장 변수들
  Map<String, dynamic>? weekSummary;
  List<double> monthlyDistances = [];
  List<String> monthlyLabels = [];
  Map<String, dynamic>? latestSummary;

  @override
  void initState() {
    super.initState();
    _loadAllStats();
  }

  /// ✅ 모든 통계 API 병렬 호출
  Future<void> _loadAllStats() async {
    try {
      final results = await Future.wait([
        _fetchWeekStats(),
        StatsService.fetchMonthlyStats(),
        StatsService.fetchLatestSummary(),
      ]);

      final week = results[0] as Map<String, dynamic>;
      final monthly = results[1] as List<Map<String, dynamic>>;
      final latest = results[2] as Map<String, dynamic>;

      setState(() {
        weekSummary = week;

        // ✅ 월별 데이터 파싱 (m → km)
        monthlyDistances = monthly
            .map<double>((e) => ((e['distance'] ?? 0) / 1000.0).toDouble())
            .toList();

        monthlyLabels = monthly
            .map<String>((e) => (e['month'] ?? '').toString().substring(5))
            .toList();

        latestSummary = latest;
        isLoading = false;
      });

    } catch (e) {
      debugPrint("❌ Failed to load stats: $e");
      setState(() => isLoading = false);
    }
  }

  /// ✅ 이번 주 통계 불러오기 (거리, 상승고도 등)
  Future<Map<String, dynamic>> _fetchWeekStats() async {
    final uri = Uri.parse('${StatsService.baseUrl}/stats?range=week');
    final res = await http.get(uri);

    if (res.statusCode == 200) {
      return json.decode(res.body);
    } else {
      throw Exception("Failed to load week stats");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// ✅ “This Week” 카드
            WeekSummaryCard(
              distance: ((weekSummary?['distance'] ?? 0.0) / 1000.0).toStringAsFixed(1),
              elevation: (weekSummary?['ascent'] ?? 0.0).toStringAsFixed(0),
              calories: (weekSummary?['calories'] ?? 0.0).toStringAsFixed(0),
            ),

            const SizedBox(height: 16),

            /// ✅ 월별 누적 그래프
            StatsChart(
              distances: monthlyDistances,
              months: monthlyLabels,
            ),

            const SizedBox(height: 24),

            /// ✅ 리스트 요약 (Activities, Statistics)
            StatsListSection(
              latestActivityDate: latestSummary?['latest_activity_date'] ?? "-",
              totalDistance:
              (latestSummary?['total_distance_km'] ?? 0.0).toDouble(),
            ),
          ],
        ),
      ),
    );
  }
}
