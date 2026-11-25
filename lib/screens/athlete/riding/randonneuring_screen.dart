import 'package:flutter/material.dart';

import '../../../models/athlete_section.dart';
import '../../../models/randonneuring.dart';
import '../../../services/api_client.dart';
import '../../../services/randonneuring_api.dart';
import '../../../utils/format.dart';
import '../../../widgets/status_message.dart';
import 'ride_route_map.dart';

// 라이딩 기록 > 랜도너스 계획: 내 기록(요약 · 올해 SR 시리즈) · 협회 브레베 일정 · 퍼머넌트 코스
class RandonneuringScreen extends StatefulWidget {
  const RandonneuringScreen({super.key, this.api, this.now});

  final RandonneuringApi? api;
  final DateTime? now; // 테스트에서 '올해' 고정용

  @override
  State<RandonneuringScreen> createState() => _RandonneuringScreenState();
}

class _RandonneuringScreenState extends State<RandonneuringScreen> {
  static final _color = AthleteSection.riding.color;

  late final RandonneuringApi _api = widget.api ?? RandonneuringApi();

  // 탭마다 처음 열 때 한 번 받음 (퍼머넌트는 응답이 커서 미리 받지 않음)
  late final Future<List<RandoResult>> _results = _api.fetchResults();
  Future<List<BrevetEvent>>? _schedule;
  Future<List<PermanentCourse>>? _permanents;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          title: const Text('랜도너스'),
          bottom: TabBar(
            indicatorColor: _color,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white.withValues(alpha: 0.55),
            tabs: const [
              Tab(text: '내 기록'),
              Tab(text: '브레베 일정'),
              Tab(text: '퍼머넌트'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _Loader(
              load: () => _results,
              color: _color,
              builder: (items) => _ResultsTab(
                items: items,
                career: RandoCareer(items, now: widget.now),
                color: _color,
              ),
            ),
            _Loader(
              load: () => _schedule ??= _api.fetchSchedule(),
              color: _color,
              builder: (events) => _ScheduleTab(events: events, color: _color),
            ),
            _Loader(
              load: () => _permanents ??= _api.fetchPermanents(),
              color: _color,
              loadingText: '퍼머넌트 코스를 받는 중 (경로 포함이라 조금 걸려요)',
              builder: (courses) => _PermanentTab(
                courses: courses,
                results: _results,
                color: _color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 탭이 처음 화면에 그려질 때 load 를 불러 기다렸다가 그리기. 실패하면 안내
// (TabBarView 는 보이는 탭만 build 하므로, 퍼머넌트 탭을 열기 전에는 받지 않음)
class _Loader<T> extends StatelessWidget {
  const _Loader({
    required this.load,
    required this.color,
    required this.builder,
    this.loadingText,
  });

  final Future<T> Function() load;
  final Color color;
  final Widget Function(T data) builder;
  final String? loadingText;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: load(),
      builder: (context, snap) {
        if (snap.hasError) {
          final e = snap.error;
          return StatusMessage(
            icon: Icons.cloud_off,
            title: e is ApiException ? e.message : '불러오지 못했어요',
            color: color,
          );
        }
        if (!snap.hasData) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                if (loadingText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    loadingText!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          );
        }
        return builder(snap.data as T);
      },
    );
  }
}

// ── 내 기록 ──────────────────────────────────────

class _ResultsTab extends StatelessWidget {
  const _ResultsTab({
    required this.items,
    required this.career,
    required this.color,
  });

  final List<RandoResult> items;
  final RandoCareer career;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.55);
    if (items.isEmpty) {
      return StatusMessage(
        icon: Icons.flag_outlined,
        title: '공식 기록이 없어요',
        detail: '웹에서 KORA 기록을 가져오면 여기 보여요',
        color: color,
      );
    }
    final c = career;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _Panel(
          child: Row(
            children: [
              _Stat(label: '완주 / 출전', value: '${c.finishes} / ${c.starts}'),
              _Stat(
                label: '완주 거리',
                value: '${formatThousands(c.finishedKm)} km',
              ),
              _Stat(
                label: '최장 완주',
                value: c.longest == null ? '-' : '${c.longest!.distanceKm} km',
              ),
            ],
          ),
        ),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${c.year} 슈퍼 랜도너 시리즈 (브레베 완주)',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final d in RandoCareer.srSeries)
                    Expanded(
                      child: _SeriesChip(
                        label: '$d',
                        done: c.yearBrevets.contains(d),
                        color: color,
                      ),
                    ),
                ],
              ),
              if (c.yearSr) ...[
                const SizedBox(height: 8),
                Text(
                  '올해 시리즈를 모두 완주했어요',
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
        ),
        const _Title('참가 기록'),
        for (final r in items) _ResultTile(result: r, color: color),
      ],
    );
  }
}

class _SeriesChip extends StatelessWidget {
  const _SeriesChip({
    required this.label,
    required this.done,
    required this.color,
  });

  final String label;
  final bool done;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: done ? color.withValues(alpha: 0.2) : Colors.transparent,
        border: Border.all(
          color: done ? color : Colors.white.withValues(alpha: 0.15),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: done ? color : Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result, required this.color});

  final RandoResult result;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.55);
    final r = result;
    final time = r.ridingTimeSec;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatDate(r.date)} · ${r.typeLabel} · ${r.distanceKm} km',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                if (r.notes case final n? when n.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      n.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                r.finished ? '완주' : 'DNF',
                style: TextStyle(
                  color: r.finished ? color : Colors.redAccent.shade100,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (r.finished && time != null)
                Text(
                  formatClock(time),
                  style: TextStyle(color: muted, fontSize: 12),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── 브레베 일정 ──────────────────────────────────

class _ScheduleTab extends StatefulWidget {
  const _ScheduleTab({required this.events, required this.color});

  final List<BrevetEvent> events;
  final Color color;

  @override
  State<_ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends State<_ScheduleTab> {
  static const _filters = ['전체', '200', '300', '400', '600', '1000+'];
  String _filter = '전체';

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.55);
    final shown = [
      for (final e in widget.events)
        if (_filter == '전체' || e.bucket == _filter) e,
    ];
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            children: [
              for (final f in _filters)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(f == '전체' ? f : '$f km'),
                    selected: _filter == f,
                    selectedColor: widget.color.withValues(alpha: 0.3),
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? StatusMessage(
                  icon: Icons.event_busy,
                  title: '해당 거리 일정이 없어요',
                  color: widget.color,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: shown.length,
                  itemBuilder: (_, i) {
                    final e = shown[i];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                      ),
                      leading: SizedBox(
                        width: 64,
                        child: Text(
                          e.date,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      title: Text(e.name),
                      subtitle: Text(
                        e.region,
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                      trailing: e.open
                          ? Text(
                              '신청 가능',
                              style: TextStyle(
                                color: widget.color,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── 퍼머넌트 ─────────────────────────────────────

class _PermanentTab extends StatefulWidget {
  const _PermanentTab({
    required this.courses,
    required this.results,
    required this.color,
  });

  final List<PermanentCourse> courses;
  final Future<List<RandoResult>> results; // 완주한 코스 표시용
  final Color color;

  @override
  State<_PermanentTab> createState() => _PermanentTabState();
}

class _PermanentTabState extends State<_PermanentTab> {
  String _query = '';
  bool _onlyTodo = false;
  Set<String> _done = {};

  @override
  void initState() {
    super.initState();
    widget.results.then((items) {
      if (!mounted) return;
      setState(() {
        _done = {
          for (final r in items)
            if (r.finished && r.permanentNo != null) r.permanentNo!,
        };
      });
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.55);
    final shown = [
      for (final c in widget.courses)
        if (c.matches(_query) && !(_onlyTodo && _done.contains(c.no))) c,
    ];
    final doneCourses = widget.courses
        .map((c) => c.no)
        .toSet()
        .where(_done.contains)
        .length;
    final allCourses = widget.courses.map((c) => c.no).toSet().length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              isDense: true,
              hintText: '코스 번호나 이름 (PT-87, 진도)',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '완주 $doneCourses / $allCourses 코스',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ),
              FilterChip(
                label: const Text('안 가본 코스만'),
                selected: _onlyTodo,
                selectedColor: widget.color.withValues(alpha: 0.3),
                onSelected: (v) => setState(() => _onlyTodo = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: shown.length,
            itemBuilder: (_, i) {
              final c = shown[i];
              final done = _done.contains(c.no);
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Icon(
                  done ? Icons.check_circle : Icons.route,
                  color: done ? widget.color : muted,
                ),
                title: Text('${c.no} ${c.name}'),
                subtitle: Text(
                  [
                    if (c.distanceKm != null) '${c.distanceKm} km',
                    if (c.timeLimit != null) '제한 ${c.timeLimit}',
                    if (c.gpxLabel != null && c.gpxLabel != c.no) c.gpxLabel!,
                  ].join(' · '),
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                trailing: Icon(Icons.chevron_right, color: muted),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _PermanentDetail(
                      course: c,
                      done: done,
                      color: widget.color,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PermanentDetail extends StatelessWidget {
  const _PermanentDetail({
    required this.course,
    required this.done,
    required this.color,
  });

  final PermanentCourse course;
  final bool done;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = course;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(c.no),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Text(
            c.name,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          if (done)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '완주한 코스예요',
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
            ),
          const SizedBox(height: 12),
          _Panel(
            child: Row(
              children: [
                _Stat(
                  label: '거리',
                  value: c.distanceKm == null ? '-' : '${c.distanceKm} km',
                ),
                _Stat(label: '제한 시간', value: c.timeLimit ?? '-'),
                _Stat(label: 'GPX', value: c.gpxLabel ?? '-'),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 360,
              child: RideRouteMap(
                route: c.route,
                color: color,
                interactive: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 공통 ─────────────────────────────────────────

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    );
  }
}
