import 'package:flutter/material.dart';

import '../models/day_event.dart';
import '../models/persona.dart';
import 'diary_api.dart';
import 'fitness_api.dart';
import 'ride_api.dart';

// 하루 동안 있었던 일을 페르소나별 데이터에서 모음.
// 지금은 애슬리트(운동 기록 · 라이딩)와 인간(하루 일기)이 서버에 있고, 개발자 · 증권은 연동 준비 중
class DailyEventSource {
  DailyEventSource({FitnessApi? fitness, RideApi? rides, DiaryApi? diary})
    : _fitness = fitness ?? FitnessApi(),
      _rides = rides ?? RideApi(),
      _diary = diary ?? DiaryApi();

  final FitnessApi _fitness;
  final RideApi _rides;
  final DiaryApi _diary;

  Future<DayEvents> load(DateTime day) async {
    final events = <DayEvent>[];
    final failed = <Persona>{};

    // 한 곳이 실패해도 나머지는 보여줌
    final sources = <(Persona, Future<List<DayEvent>>)>[
      (Persona.athlete, _workouts(day)),
      (Persona.athlete, _rideEvents(day)),
      (Persona.human, _diaryEvents(day)),
    ];
    final results = await Future.wait([
      for (final (_, f) in sources)
        f.then<List<DayEvent>?>((e) => e).catchError((_) => null),
    ]);
    for (var i = 0; i < sources.length; i++) {
      final r = results[i];
      if (r == null) {
        failed.add(sources[i].$1);
      } else {
        events.addAll(r);
      }
    }
    return DayEvents(
      events: events,
      connected: const {Persona.athlete, Persona.human},
      failed: failed,
    );
  }

  Future<List<DayEvent>> _workouts(DateTime day) async {
    final sessions = await _fitness.fetchHistory(day);
    return [
      for (final s in sessions)
        if (_sameDay(s.date, day))
          DayEvent(
            persona: Persona.athlete,
            icon: Icons.fitness_center,
            title: s.isPT ? 'PT 웨이트' : '웨이트 운동',
            detail: [
              '${s.exercises.length}종목',
              if (s.totalSets != null) '${s.totalSets}세트',
              if (s.estimatedMinutes != null) '약 ${s.estimatedMinutes}분',
              if (s.estimatedCalories != null)
                '${s.estimatedCalories!.round()}kcal',
            ].join(' · '),
          ),
    ];
  }

  Future<List<DayEvent>> _rideEvents(DateTime day) async {
    final rides = await _rides.fetchRides();
    return [
      for (final r in rides)
        if (_sameDay(r.startTime, day))
          DayEvent(
            persona: Persona.athlete,
            icon: Icons.directions_bike,
            time: r.startTime,
            title: r.title,
            detail: [
              if (r.distanceMeters != null)
                '${(r.distanceMeters! / 1000).toStringAsFixed(1)}km',
              if (r.movingSeconds != null) '${r.movingSeconds! ~/ 60}분',
              if (r.calories != null) '${r.calories}kcal',
            ].join(' · '),
          ),
    ];
  }

  // 그날 일기 한 편 → 시각 없는 이벤트 하나 (본문 첫 줄을 미리보기로)
  Future<List<DayEvent>> _diaryEvents(DateTime day) async {
    final d = await _diary.fetch(day);
    if (d == null) return const [];
    final firstLine = d.body
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    return [
      DayEvent(
        persona: Persona.human,
        icon: Icons.menu_book,
        title: d.title?.isNotEmpty == true ? d.title! : '하루 일기',
        detail: firstLine.length > 60
            ? '${firstLine.substring(0, 60)}…'
            : firstLine,
      ),
    ];
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
