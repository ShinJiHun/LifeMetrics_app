import 'package:flutter/material.dart';

import '../models/day_event.dart';
import '../models/diary.dart';
import '../models/persona.dart';
import 'api_client.dart';
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
    final locked = <Persona>{};

    // 한 곳이 실패해도 나머지는 보여줌
    final sources = <(Persona, Future<List<DayEvent>>)>[
      (Persona.athlete, _workouts(day)),
      (Persona.athlete, _rideEvents(day)),
      (Persona.human, _diaryEvents(day, locked)),
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
      locked: locked,
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

  // 일기 메모 · 초안 → 인간 이벤트. 메모는 저장 시각에, 일기는 시각 없는 하루 이벤트로.
  // 일기 API 는 관리자 전용이라 로그인 전이면 locked 에 표시하고 빈 목록
  Future<List<DayEvent>> _diaryEvents(DateTime day, Set<Persona> locked) async {
    final DiaryDay d;
    try {
      d = await _diary.fetchDay(day);
    } on AdminRequiredException {
      locked.add(Persona.human);
      return const [];
    }
    String preview(String text) {
      final line = text
          .split('\n')
          .map((l) => l.trim())
          .firstWhere((l) => l.isNotEmpty, orElse: () => '');
      return line.length > 60 ? '${line.substring(0, 60)}…' : line;
    }

    return [
      for (final n in d.notes)
        DayEvent(
          persona: Persona.human,
          icon: Icons.sticky_note_2_outlined,
          time: n.createdAt,
          title: '메모 · ${n.sourceLabel}',
          detail: preview(n.content),
        ),
      for (final e in [d.diary, d.book])
        if (e != null)
          DayEvent(
            persona: Persona.human,
            icon: e.isBook ? Icons.menu_book : Icons.auto_stories,
            title: e.title.isNotEmpty ? e.title : (e.isBook ? '독서 기록' : '하루 일기'),
            detail: [
              e.isPublished ? '게시함' : '초안',
              preview(e.content),
            ].where((s) => s.isNotEmpty).join(' · '),
          ),
    ];
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
