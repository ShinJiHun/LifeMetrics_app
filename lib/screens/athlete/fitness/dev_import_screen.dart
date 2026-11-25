import 'package:flutter/material.dart';

import '../../../models/athlete_section.dart';
import '../../../models/workout.dart';
import '../../../services/api_client.dart';
import '../../../services/dev_import_service.dart';
import '../../../utils/format.dart';
import '../../../widgets/admin_login_dialog.dart';
import '../../../widgets/bottom_action_bar.dart';
import '../../../widgets/status_message.dart';

// 개발 서버에만 있는 운동 기록(이번 달 · 지난달)과 일기(최근 60일)를 골라 운영으로 옮김
class DevImportScreen extends StatefulWidget {
  const DevImportScreen({super.key, this.service, this.now});

  final DevImportService? service;
  final DateTime? now; // 테스트에서 '이번 달' 고정용

  @override
  State<DevImportScreen> createState() => _DevImportScreenState();
}

class _DevImportScreenState extends State<DevImportScreen> {
  static final _color = AthleteSection.fitness.color;

  late final DevImportService _service = widget.service ?? DevImportService();

  List<DevMissing>? _workouts;
  List<DiaryCandidate>? _diaries;
  final Set<int> _pickedWorkouts = {}; // 개발 서버 세션 id
  final Set<String> _pickedDiaries = {}; // 날짜
  bool _privatePosts = true; // 게시했던 일기를 운영에서 비공개로
  String? _error;
  bool _loading = true;
  bool _copying = false;
  int _done = 0;

  int get _pickedCount => _pickedWorkouts.length + _pickedDiaries.length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool askedLogin = false}) async {
    final now = widget.now ?? DateTime.now();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ignored = await DevImportService.loadIgnored();
      final workouts = await _service.findMissing([
        DateTime(now.year, now.month),
        DateTime(now.year, now.month - 1),
      ], ignored: ignored);
      final diaries = await _service.findMissingDiaries();
      if (!mounted) return;
      setState(() {
        _workouts = workouts;
        _diaries = diaries;
        // 운영에 그날 기록이 아예 없는 것만 미리 체크. 일부만 다른 날은 테스트일 수 있어 직접 고르게
        _pickedWorkouts
          ..clear()
          ..addAll([
            for (final m in workouts)
              if (!m.partial) m.session.id,
          ]);
        _pickedDiaries
          ..clear()
          ..addAll([
            for (final d in diaries)
              if (!d.partial) d.date,
          ]);
        _loading = false;
      });
    } on AdminRequiredException {
      // 일기는 조회도 관리자 전용 (개발 · 운영 모두). 로그인 후 한 번만 다시
      if (!mounted) return;
      if (!askedLogin &&
          await loginAdminWithDialog(context, _service.loginAdmin)) {
        return _load(askedLogin: true);
      }
      if (mounted) {
        setState(() {
          _error = '관리자 로그인이 필요해요';
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  // 관리자 요청: 세션이 없으면 지문(또는 비밀번호) 로그인 후 한 번 더
  Future<bool> _admin(Future<void> Function() call) async {
    try {
      await call();
      return true;
    } on AdminRequiredException {
      if (!mounted ||
          !await loginAdminWithDialog(context, _service.loginAdmin)) {
        return false;
      }
      await call();
      return true;
    }
  }

  Future<void> _copy() async {
    if (_copying) return; // 빠르게 두 번 눌러도 한 번만
    _copying = true;
    final messenger = ScaffoldMessenger.of(context);
    final workouts = [
      for (final m in _workouts ?? const <DevMissing>[])
        if (_pickedWorkouts.contains(m.session.id)) m.session,
    ];
    final diaries = [
      for (final d in _diaries ?? const <DiaryCandidate>[])
        if (_pickedDiaries.contains(d.date)) d,
    ];
    setState(() => _done = 0);
    try {
      for (final s in workouts) {
        if (!await _admin(() => _service.copyToProd(s))) return;
        if (mounted) setState(() => _done++);
      }
      for (final d in diaries) {
        if (!await _admin(
          () => _service.copyDiary(d, private: _privatePosts),
        )) {
          return;
        }
        if (mounted) setState(() => _done++);
      }
      messenger.showSnackBar(
        SnackBar(content: Text('운영 서버로 ${workouts.length + diaries.length}개 옮겼어요')),
      );
      await _load(); // 옮긴 건 목록에서 빠짐
    } on ApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('$_done개 옮긴 뒤 멈췄어요: ${e.message}')),
      );
    } finally {
      _copying = false;
      if (mounted) setState(() {});
    }
  }

  // 테스트로 넣은 운동 등: 폰에 기억해 두고 다음부터 목록에서 뺌
  Future<void> _hide(WorkoutSession s) async {
    await DevImportService.ignore(s);
    if (!mounted) return;
    setState(() {
      _workouts = [
        for (final m in _workouts ?? const <DevMissing>[])
          if (m.session.id != s.id) m,
      ];
      _pickedWorkouts.remove(s.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final workouts = _workouts ?? const <DevMissing>[];
    final diaries = _diaries ?? const <DiaryCandidate>[];
    final empty = workouts.isEmpty && diaries.isEmpty;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('개발 서버 기록 옮기기'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? StatusMessage(
              icon: Icons.cloud_off,
              title: _error!,
              color: _color,
              action: '다시 시도',
              onAction: _load,
            )
          : empty
          ? StatusMessage(
              icon: Icons.check_circle_outline,
              title: '옮길 기록이 없어요',
              detail: '개발 서버의 운동 · 일기가 모두 운영에 있어요',
              color: _color,
            )
          : _list(workouts, diaries),
      bottomNavigationBar: !_loading && _error == null && !empty
          ? BottomActionBar(
              child: FilledButton(
                onPressed: _copying || _pickedCount == 0 ? null : _copy,
                style: FilledButton.styleFrom(
                  backgroundColor: _color,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(
                  _copying
                      ? '옮기는 중 ($_done/$_pickedCount)'
                      : '운영 서버로 옮기기 ($_pickedCount개)',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _list(List<DevMissing> workouts, List<DiaryCandidate> diaries) {
    final muted = Colors.white.withValues(alpha: 0.55);
    final amber = Colors.amber.shade200;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Text(
          '개발 서버에만 있는 기록이에요. 옮길 것만 체크하세요. '
          '운영에 그날 기록이 이미 있는 날은 체크를 빼 뒀어요',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        if (workouts.isNotEmpty) ...[
          const _Title('운동'),
          for (final m in workouts)
            CheckboxListTile(
              value: _pickedWorkouts.contains(m.session.id),
              activeColor: _color,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: _copying
                  ? null
                  : (v) => setState(() {
                      if (v == true) {
                        _pickedWorkouts.add(m.session.id);
                      } else {
                        _pickedWorkouts.remove(m.session.id);
                      }
                    }),
              title: Text(
                '${formatDate(m.session.date)}${m.session.isPT ? ' · PT' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (m.partial)
                    Text(
                      '운영에 이날 기록이 있어요. 아래는 개발 서버에만 있는 운동',
                      style: TextStyle(color: amber, fontSize: 12),
                    ),
                  Text(
                    [
                      for (final e in m.session.exercises)
                        '${e.nameKo ?? '운동'} ${e.brief}',
                    ].join(' · '),
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
              secondary: IconButton(
                tooltip: '다시 안 보기',
                icon: Icon(Icons.visibility_off_outlined, color: muted),
                onPressed: _copying ? null : () => _hide(m.session),
              ),
            ),
        ],
        if (diaries.isNotEmpty) ...[
          const _Title('일기'),
          for (final d in diaries)
            CheckboxListTile(
              value: _pickedDiaries.contains(d.date),
              activeColor: _color,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: _copying
                  ? null
                  : (v) => setState(() {
                      if (v == true) {
                        _pickedDiaries.add(d.date);
                      } else {
                        _pickedDiaries.remove(d.date);
                      }
                    }),
              title: Text(
                formatDate(DateTime.parse(d.date)),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (d.partial)
                    Text(
                      '운영에 이날 메모 · 일기가 이미 있어요 (옮기면 메모가 더해져요)',
                      style: TextStyle(color: amber, fontSize: 12),
                    ),
                  Text(
                    d.summary,
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          if (diaries.any((d) => d.published))
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text('게시했던 일기는 비공개로 게시'),
              subtitle: Text(
                '운영 블로그에 올릴 때 공개 범위 (일기 초안 → 개발 서버 최종본으로 덮어쓴 뒤 게시)',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              value: _privatePosts,
              activeThumbColor: _color,
              onChanged: _copying
                  ? null
                  : (v) => setState(() => _privatePosts = v),
            ),
        ],
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    );
  }
}
