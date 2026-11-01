import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../models/body_record.dart';
import '../../../utils/format.dart';

// 선택한 지표 하나의 추이 (단일 y축). 터치하면 날짜와 값 툴팁
class InbodyTrendChart extends StatelessWidget {
  const InbodyTrendChart({
    super.key,
    required this.records,
    required this.metric,
    required this.color,
  });

  final List<BodyRecord> records; // 날짜 오름차순, 모두 metric 값이 있어야 함
  final BodyMetric metric;
  final Color color;

  static const _surface = Color(0xFF211E36);
  static const _muted = Color(0x99FFFFFF);

  static double _day(DateTime d) =>
      d.millisecondsSinceEpoch / Duration.millisecondsPerDay;

  @override
  Widget build(BuildContext context) {
    final values = records.map((r) => metric.valueOf(r)!).toList();
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);

    // 값 범위에 맞춰 1 / 2 / 5 단위의 깔끔한 눈금 계산
    final raw = math.max(hi - lo, 1.0) / 4;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final step = [1, 2, 5, 10].map((m) => m * mag).firstWhere((s) => s >= raw);
    final minY = (lo / step).floor() * step - step;
    final maxY = (hi / step).ceil() * step + step;

    // 양 끝 점이 잘리지 않도록 x 범위에 여유 (모든 기록이 같은 날이어도 하루씩)
    final first = _day(records.first.date);
    final last = _day(records.last.date);
    final padX = math.max((last - first) * 0.04, 1.0);
    final minX = first - padX;
    final maxX = last + padX;

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: step,
          getDrawingHorizontalLine: (_) => FlLine(
            color: Colors.white.withValues(alpha: 0.06),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: step,
              minIncluded: false,
              maxIncluded: false,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                child: Text(
                  formatNum(value),
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
              ),
            ),
          ),
          // 첫 기록과 마지막 기록 날짜만 표시
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final DateTime date;
                if (value.round() == first.round()) {
                  date = records.first.date;
                } else if (value.round() == last.round() && last != first) {
                  date = records.last.date;
                } else {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                  child: Text(
                    formatShortDate(date),
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchSpotThreshold: 24,
          getTouchedSpotIndicator: (bar, indexes) => [
            for (final _ in indexes)
              TouchedSpotIndicatorData(
                FlLine(
                  color: Colors.white.withValues(alpha: 0.25),
                  strokeWidth: 1,
                ),
                FlDotData(
                  getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                    radius: 6,
                    color: color,
                    strokeWidth: 2,
                    strokeColor: _surface,
                  ),
                ),
              ),
          ],
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF34305A),
            tooltipBorderRadius: BorderRadius.circular(10),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${formatDate(records[s.spotIndex].date)}\n',
                  const TextStyle(color: _muted, fontSize: 11),
                  children: [
                    TextSpan(
                      text: '${formatNum(s.y)} ${metric.unit}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (final r in records) FlSpot(_day(r.date), metric.valueOf(r)!),
            ],
            color: color,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(
              getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                radius: 4,
                color: color,
                strokeWidth: 2,
                strokeColor: _surface,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}
