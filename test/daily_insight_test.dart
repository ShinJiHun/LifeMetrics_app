import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lifemetrics_app/models/day_event.dart';
import 'package:lifemetrics_app/models/persona.dart';
import 'package:lifemetrics_app/screens/daily_insight_screen.dart';

void main() {
  final now = DateTime(2026, 11, 16, 23);

  DayEvents sample(DateTime day) => DayEvents(
    connected: const {Persona.athlete},
    events: [
      const DayEvent(
        persona: Persona.athlete,
        icon: Icons.fitness_center,
        title: '웨이트 운동',
        detail: '5종목',
      ),
      DayEvent(
        persona: Persona.athlete,
        icon: Icons.directions_bike,
        time: DateTime(day.year, day.month, day.day, 7, 5),
        title: '아침 라이딩',
      ),
    ],
  );

  testWidgets('기본은 어제, 시각 있는 이벤트가 먼저, 연동 안 된 페르소나 안내', (tester) async {
    final asked = <DateTime>[];
    await tester.pumpWidget(
      MaterialApp(
        home: DailyInsightScreen(
          now: now,
          loader: (d) async {
            asked.add(d);
            return sample(d);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(asked.single, DateTime(2026, 11, 15));
    expect(find.textContaining('11월 15일 (일) · 어제'), findsOneWidget);
    expect(find.text('07:05'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('아침 라이딩')).dy,
      lessThan(tester.getTopLeft(find.text('웨이트 운동')).dy),
    );
    expect(find.textContaining('이벤트 2개가 모였어요'), findsOneWidget);
    expect(find.text('인간 · 개발자 · 증권 데이터는 아직 연동 준비 중이에요'), findsOneWidget);

    // 오늘 이후로는 못 넘어감
    await tester.tap(find.byTooltip('다음날'));
    await tester.pumpAndSettle();
    expect(find.textContaining('· 오늘'), findsOneWidget);
    await tester.tap(find.byTooltip('다음날'));
    await tester.pumpAndSettle();
    expect(asked.last, DateTime(2026, 11, 16));
  });

  testWidgets('페르소나를 고르면 그 이벤트만, 연동 전이면 준비 중 안내', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DailyInsightScreen(now: now, loader: (d) async => sample(d)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('개발자'));
    await tester.pumpAndSettle();
    expect(find.text('아침 라이딩'), findsNothing);
    expect(find.text('개발자 데이터는 아직 연동 준비 중이에요'), findsOneWidget);

    await tester.tap(find.text('애슬리트 2'));
    await tester.pumpAndSettle();
    expect(find.text('아침 라이딩'), findsOneWidget);
  });
}
