import 'package:flutter/material.dart';

import 'persona.dart';

// 종합 분석의 하루 타임라인에 올라가는 일 하나 (운동 · 라이딩 · 커밋 · 매매 ...)
class DayEvent {
  const DayEvent({
    required this.persona,
    required this.title,
    required this.icon,
    this.time,
    this.detail,
  });

  final Persona persona;
  final String title;
  final IconData icon;
  final DateTime? time; // 시각을 모르는 기록(날짜만 있는 운동 등)은 null
  final String? detail;
}

// 하루치 이벤트 + 페르소나별로 데이터를 가져왔는지
class DayEvents {
  const DayEvents({
    required this.events,
    this.connected = const {},
    this.failed = const {},
  });

  final List<DayEvent> events;
  final Set<Persona> connected; // 데이터 연동이 된 페르소나
  final Set<Persona> failed; // 연동은 됐지만 이번에 불러오지 못함

  // 시각 있는 것 순서대로, 시각 모르는 건 맨 아래
  List<DayEvent> sorted({Persona? only}) {
    final list = [
      for (final e in events)
        if (only == null || e.persona == only) e,
    ];
    list.sort((a, b) {
      final ta = a.time, tb = b.time;
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return ta.compareTo(tb);
    });
    return list;
  }

  int countOf(Persona p) => events.where((e) => e.persona == p).length;
}
