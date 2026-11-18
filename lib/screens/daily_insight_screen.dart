import 'package:flutter/material.dart';

import '../models/day_event.dart';
import '../models/persona.dart';
import '../services/daily_events.dart';

// 종합 분석: 개발자 · 인간 · 애슬리트 · 증권에서 하루 동안 있었던 일을 시간순으로 모아 보여주고,
// 그 이벤트를 바탕으로 쓴 하루 일과 분석 글이 들어갈 자리
class DailyInsightScreen extends StatefulWidget {
  const DailyInsightScreen({super.key, this.now, this.loader});

  final DateTime? now; // 테스트에서 '오늘' 고정용
  final Future<DayEvents> Function(DateTime day)? loader;

  @override
  State<DailyInsightScreen> createState() => _DailyInsightScreenState();
}

class _DailyInsightScreenState extends State<DailyInsightScreen> {
  static const _bg = Color(0xFF15122B);
  static const _accent = Color(0xFF7C6CF2);

  late final DateTime _today = _dateOnly(widget.now ?? DateTime.now());
  // 하루가 다 지나야 분석할 수 있으므로 기본은 어제
  late DateTime _day = _today.subtract(const Duration(days: 1));
  Persona? _filter;
  late Future<DayEvents> _future = _load();

  Future<DayEvents> _load() => (widget.loader ?? DailyEventSource().load)(_day);

  void _moveDay(int delta) {
    final next = _day.add(Duration(days: delta));
    if (next.isAfter(_today)) return;
    setState(() {
      _day = next;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('종합 분석'),
      ),
      body: SafeArea(
        top: false,
        child: FutureBuilder<DayEvents>(
          future: _future,
          builder: (context, snap) {
            final data = snap.data;
            return RefreshIndicator(
              onRefresh: () async {
                setState(() => _future = _load());
                await _future;
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  _dateBar(),
                  const SizedBox(height: 16),
                  _personaChips(data),
                  const SizedBox(height: 16),
                  _analysisCard(data),
                  const SizedBox(height: 24),
                  const Text(
                    '하루 이벤트',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (snap.connectionState != ConnectionState.done)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (data == null)
                    _note('이벤트를 불러오지 못했어요. 아래로 당겨 다시 시도해 주세요')
                  else
                    ..._timeline(data),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _dateBar() {
    const week = ['월', '화', '수', '목', '금', '토', '일'];
    final label = _day == _today
        ? '오늘'
        : _day == _today.subtract(const Duration(days: 1))
        ? '어제'
        : null;
    return Row(
      children: [
        IconButton(
          tooltip: '전날',
          color: Colors.white,
          icon: const Icon(Icons.chevron_left),
          onPressed: () => _moveDay(-1),
        ),
        Expanded(
          child: Text(
            '${_day.month}월 ${_day.day}일 (${week[_day.weekday - 1]})'
            '${label == null ? '' : ' · $label'}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          tooltip: '다음날',
          color: Colors.white,
          disabledColor: Colors.white24,
          icon: const Icon(Icons.chevron_right),
          onPressed: _day == _today ? null : () => _moveDay(1),
        ),
      ],
    );
  }

  Widget _personaChips(DayEvents? data) {
    Widget chip(String text, Color color, Persona? p) {
      final selected = _filter == p;
      return ChoiceChip(
        label: Text(text),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => setState(() => _filter = p),
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.white70,
          fontWeight: FontWeight.w600,
        ),
        selectedColor: color.withValues(alpha: 0.35),
        backgroundColor: Colors.white.withValues(alpha: 0.05),
        side: BorderSide(
          color: selected ? color : Colors.white.withValues(alpha: 0.1),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip('전체 ${data?.events.length ?? ''}'.trim(), _accent, null),
        for (final p in Persona.values)
          chip(
            data != null && data.connected.contains(p)
                ? '${p.title} ${data.countOf(p)}'
                : p.title,
            p.color,
            p,
          ),
      ],
    );
  }

  // 하루 일과 분석 글. 이벤트를 모아 AI 가 쓰는 기능은 서버 작업 후 연결
  Widget _analysisCard(DayEvents? data) {
    final count = data?.events.length ?? 0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            for (final p in Persona.values) p.color.withValues(alpha: 0.22),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                '하루 일과 분석',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            count == 0
                ? '이날 모인 이벤트가 없어요. 이벤트가 쌓이면 개발 · 일상 · 운동 · 투자를 엮어 '
                      '하루를 돌아보는 글을 써 드려요.'
                : '이벤트 $count개가 모였어요. 이 기록을 바탕으로 개발 · 일상 · 운동 · 투자를 엮어 '
                      '하루를 돌아보는 글을 써 드릴 예정이에요.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: null, // 서버의 분석 글 생성 API 가 생기면 연결
              icon: const Icon(Icons.edit_note),
              label: const Text('분석 글 올리기 (준비 중)'),
              style: FilledButton.styleFrom(
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _timeline(DayEvents data) {
    final only = _filter;
    final events = data.sorted(only: only);
    // 고른 페르소나(전체면 모든 페르소나) 중 아직 연동 안 된 것 안내
    final pending = [
      for (final p in only == null ? Persona.values : [only])
        if (!data.connected.contains(p)) p.title,
    ];
    final notes = <Widget>[
      if (pending.isNotEmpty)
        _note('${pending.join(' · ')} 데이터는 아직 연동 준비 중이에요'),
      for (final p in data.failed)
        if (only == null || only == p) _note('${p.title} 기록 일부를 불러오지 못했어요'),
      for (final p in data.locked)
        if (only == null || only == p)
          _note('${p.title} 기록은 관리자 로그인 후 보여요 (${p.title} 화면에서 로그인)'),
    ];
    if (events.isEmpty) {
      return [
        if (only == null || data.connected.contains(only))
          _note('이날 기록된 이벤트가 없어요'),
        ...notes,
      ];
    }
    return [for (final e in events) _eventTile(e), ...notes];
  }

  Widget _eventTile(DayEvent e) {
    final t = e.time;
    final time = t == null
        ? '하루'
        : '${t.hour.toString().padLeft(2, '0')}:'
              '${t.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                time,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 13,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border(
                  left: BorderSide(color: e.persona.color, width: 3),
                ),
              ),
              child: Row(
                children: [
                  Icon(e.icon, color: e.persona.color, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (e.detail != null && e.detail!.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            e.detail!,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    e.persona.title,
                    style: TextStyle(
                      color: e.persona.color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.45),
        fontSize: 13,
      ),
    ),
  );

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
