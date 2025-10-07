import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class StatsChart extends StatelessWidget {
  final List<double> distances;
  final List<String> months;

  const StatsChart({
    super.key,
    required this.distances,
    required this.months,
  });

  @override
  Widget build(BuildContext context) {
    final maxY = (distances.isEmpty ? 100 : distances.reduce((a, b) => a > b ? a : b)) * 1.2;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 220,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY,
              minX: 0,
              maxX: (distances.length - 1).toDouble(),

              // ✅ 터치 시 툴팁 (소수점 2자리 + 단위 표시)
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  tooltipRoundedRadius: 8,
                  tooltipPadding: const EdgeInsets.all(8),
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((barSpot) {
                      final y = barSpot.y;
                      final formatted = y.toStringAsFixed(2); // 소수점 2자리
                      final monthIndex = barSpot.x.toInt();
                      final label = (monthIndex < months.length) ? months[monthIndex] : '';
                      return LineTooltipItem(
                        "$label\n$formatted km",
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      );
                    }).toList();
                  },
                ),
              ),

              // ✅ 축 라벨 설정
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    getTitlesWidget: (value, meta) {
                      if (value.toInt() >= months.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          months[value.toInt()],
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      );
                    },
                    interval: 1,
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    interval: maxY / 4,
                    getTitlesWidget: (value, meta) => Text(
                      "${value.toStringAsFixed(0)}",
                      style: const TextStyle(fontSize: 9, color: Colors.grey),
                    ),
                  ),
                ),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),

              // ✅ 격자선, 선, 채우기 등 스타일
              gridData: FlGridData(
                show: true,
                horizontalInterval: maxY / 4,
                getDrawingHorizontalLine: (value) =>
                    FlLine(color: Colors.grey.withOpacity(0.2), strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: List.generate(
                    distances.length,
                        (i) => FlSpot(i.toDouble(), distances[i]),
                  ),
                  isCurved: true,
                  color: Colors.orange,
                  barWidth: 3,
                  belowBarData: BarAreaData(
                    show: true,
                    color: Colors.orange.withOpacity(0.2),
                  ),
                  dotData: FlDotData(show: true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
