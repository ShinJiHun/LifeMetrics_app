import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/today_plan.dart';
import 'workout_recommend_screen.dart' show ExerciseGif;

// 유산소 입력칸 키. PlannedCardio.actual 과 같음
List<String> cardioFieldKeys(PlannedCardio c) => [
  'minutes',
  'kcal',
  'distance',
  'avgHr',
  ...c.machine.extras.map((e) => e.$1),
];

// 고른 유산소: 목표 + 실제로 한 값 입력칸
class CardioActualCard extends StatelessWidget {
  const CardioActualCard({
    super.key,
    required this.cardio,
    required this.fields,
    required this.color,
    required this.enabled,
    required this.onChanged,
  });

  final PlannedCardio cardio;
  final Map<String, TextEditingController> fields;
  final Color color;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.55);

    Widget field(
      String key,
      String label,
      String suffix, {
      bool decimal = false,
      bool colon = false, // 500m 페이스 2:05
    }) => TextField(
      controller: fields[key],
      enabled: enabled,
      onChanged: (_) => onChanged(),
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          colon
              ? RegExp(r'[\d:]')
              : decimal
              ? RegExp(r'^\d*\.?\d{0,2}')
              : RegExp(r'\d'),
        ),
      ],
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix.isEmpty ? null : suffix,
        isDense: true,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );

    // 두 칸씩 한 줄
    final inputs = [
      field('minutes', '실제 시간', '분', decimal: true),
      field('kcal', '기기 칼로리', 'kcal'),
      for (final (key, label, unit) in cardio.machine.extras)
        field(key, label, unit, decimal: key != 'pace', colon: key == 'pace'),
      field('distance', '거리', 'km', decimal: true),
      field('avgHr', '평균 심박', 'bpm'),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox.square(
                  dimension: 88,
                  child: ExerciseGif(url: cardio.gifUrl, cacheWidth: 264),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '유산소 · ${cardio.name}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '목표 ${cardio.targetMinutes}분 · 약 ${cardio.targetKcal}kcal · ${cardio.intensity}',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      cardio.how,
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (cardio.itemId == null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '서버에 이 기구 종목이 없어 기록은 저장되지 않아요',
                style: TextStyle(color: Colors.amber.shade200, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            '하고 나서 기기에 나온 값을 적어 주세요',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < inputs.length; i += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(child: inputs[i]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: i + 1 < inputs.length
                        ? inputs[i + 1]
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
