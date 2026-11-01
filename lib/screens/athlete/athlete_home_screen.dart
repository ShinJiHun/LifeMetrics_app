import 'package:flutter/material.dart';

import '../../models/athlete_section.dart';
import '../../widgets/category_card.dart';
import 'athlete_section_screen.dart';

// 애슬리트 홈: 4개 파트를 2x2 카드로 보여줌
class AthleteHomeScreen extends StatelessWidget {
  const AthleteHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '오늘은 무엇을 기록할까요?',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.78,
              children: [
                for (final section in AthleteSection.values)
                  CategoryCard(
                    icon: section.icon,
                    title: section.title,
                    subtitle: section.subtitle,
                    description: section.description,
                    color: section.color,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AthleteSectionScreen(section: section),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
