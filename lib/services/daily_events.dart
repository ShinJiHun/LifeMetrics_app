import 'package:flutter/material.dart';

import '../models/day_event.dart';
import '../models/persona.dart';
import 'fitness_api.dart';
import 'ride_api.dart';

// 하루 동안 있었던 일을 페르소나별 데이터에서 모음.
// 지금은 애슬리트(운동 기록 · 라이딩)만 서버에 있고, 개발자 · 인간 · 증권은 연동 준비 중
class DailyEventSource {
  DailyEventSource({FitnessApi? fitness, RideApi? rides})
    : _fitness = fitness ?? FitnessApi(),
      _rides = rides ?? RideApi();

  final FitnessApi _fitness;
  final RideApi _rides;

  Future<DayEvents> load(DateTime day) async {
    final events = <DayEvent>[];
    final failed = <Persona>{};

    // 한 곳이 실패해도 나머지는 보여줌
    final results = await Future.wait([
      _workouts(day).then<List<DayEvent>?>((e) => e).catchError((_) => null),
      _rideEvents(day).then<List<DayEvent>?>((e) => e).catchError((_) => null),
    ]);
    for (final r in results) {
      if (r == null) {
        failed.add(Persona.athlete);
      } else {
        events.addAll(r);
      }
    }
    return DayEvents(
      events: events,
      connected: const {Persona.athlete},
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

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
