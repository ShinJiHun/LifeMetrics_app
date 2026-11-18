import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/diary.dart';
import '../../models/persona.dart';
import '../../services/api_client.dart';
import '../../services/diary_api.dart';
import '../../widgets/admin_login_dialog.dart';

// 인간 페르소나: 하루 일기.
// 하루 동안 메모(Claude 앱 대화 붙여넣기 · 직접 쓴 글)를 모으면 서버가 밤 10시에 일기 초안을 쓰고,
// 여기서 확인 · 고친 뒤 인간 블로그에 게시. 서버 API 는 관리자 전용이라 처음에 비밀번호를 물음
class DiaryScreen extends StatefulWidget {
  const DiaryScreen({super.key, this.api, this.now});

  final DiaryApi? api;
  final DateTime? now; // 테스트에서 '오늘' 고정용

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  static final _color = Persona.human.color;
  static const _amber = Color(0xFFFFC857);

  late final DiaryApi _api = widget.api ?? DiaryApi();
  late final DateTime _today = _dateOnly(widget.now ?? DateTime.now());
  late DateTime _day = _today;

  DiaryDay? _data;
  bool _loading = true;
  bool _needsLogin = false;
  String? _error;
  bool _busy = false; // 저장 · 초안 만들기 · 게시 중
  String? _busyText;

  @override
  void initState() {
    super.initState();
    _load(askLogin: true);
  }

  Future<void> _load({bool askLogin = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await _api.fetchDay(_day);
      if (!mounted) return;
      setState(() {
        _data = d;
        _needsLogin = false;
        _loading = false;
      });
    } on AdminRequiredException {
      if (!mounted) return;
      setState(() {
        _needsLogin = true;
        _loading = false;
      });
      // 화면을 처음 열 때는 바로 비밀번호를 물음
      if (askLogin) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _login());
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _login() async {
    if (!mounted) return;
    if (await loginAdminWithDialog(context, _api.loginAdmin)) await _load();
  }

  // 관리자 요청 공통: 세션이 끊겼으면 로그인 후 한 번 더 시도
  Future<T?> _run<T>(String text, Future<T> Function() call) async {
    setState(() {
      _busy = true;
      _busyText = text;
    });
    try {
      try {
        return await call();
      } on AdminRequiredException {
        if (!mounted || !await loginAdminWithDialog(context, _api.loginAdmin)) {
          return null;
        }
        return await call();
      }
    } on ApiException catch (e) {
      _toast(e.message);
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyText = null;
        });
      }
    }
  }

  void _moveDay(int delta) {
    final next = _day.add(Duration(days: delta));
    if (next.isAfter(_today)) return;
    setState(() {
      _day = next;
      _data = null;
    });
    _load();
  }

  // ── 메모 ──────────────────────────────────────

  Future<void> _addNote() async {
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1A38),
      builder: (_) => const _NoteSheet(),
    );
    if (result == null) return;
    final (content, source) = result;
    final note = await _run(
      '메모 저장 중',
      () => _api.addNote(_day, content, source: source),
    );
    if (note != null) {
      _toast('메모를 저장했어요');
      await _load();
    }
  }

  Future<void> _deleteNote(DiaryNote n) async {
    if (!await _confirm('이 메모를 지울까요?')) return;
    final ok = await _run('지우는 중', () async {
      await _api.deleteNote(n.id);
      return true;
    });
    if (ok == true) await _load();
  }

  // ── 초안 ──────────────────────────────────────

  Future<void> _generate({required bool again}) async {
    if (again && !await _confirm('메모로 초안을 다시 만들까요? 고친 내용은 덮어써요.')) {
      return;
    }
    final d = await _run('초안 쓰는 중 (1분쯤 걸려요)', () => _api.generate(_day));
    if (d != null && mounted) setState(() => _data = d);
  }

  Future<void> _edit(DiaryEntry e) async {
    final result = await Navigator.of(context).push<(String, String)>(
      MaterialPageRoute(builder: (_) => _EntryEditor(entry: e)),
    );
    if (result == null) return;
    final saved = await _run(
      '저장 중',
      () => _api.updateEntry(e.id, result.$1, result.$2),
    );
    if (saved != null) {
      _toast('고친 초안을 저장했어요. 밤 10시 자동 초안이 덮어쓰지 않아요');
      await _load();
    }
  }

  Future<void> _discard(DiaryEntry e) async {
    if (!await _confirm('이 초안을 버릴까요?')) return;
    final ok = await _run('버리는 중', () async {
      await _api.discardEntry(e.id);
      return true;
    });
    if (ok == true) await _load();
  }

  Future<void> _publish(DiaryEntry e) async {
    final menus = await _run('메뉴 불러오는 중', _api.subMenus);
    if (menus == null || !mounted) return;
    final choice = await showModalBottomSheet<(int?, bool)>(
      context: context,
      backgroundColor: const Color(0xFF1E1A38),
      builder: (_) => _PublishSheet(entry: e, menus: menus),
    );
    if (choice == null) return;
    final published = await _run(
      '게시 중',
      () => _api.publish(e.id, subId: choice.$1, isPublic: choice.$2),
    );
    if (published != null) {
      _toast(choice.$2 ? '블로그에 공개로 게시했어요' : '블로그에 비공개로 게시했어요');
      await _load();
    }
  }

  // ── 화면 ──────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              _dateBar(),
              const SizedBox(height: 12),
              if (_loading && data == null)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_needsLogin)
                _loginBox()
              else if (_error != null)
                _messageBox(_error!, '다시 시도', _load)
              else if (data != null) ...[
                _notesSection(data),
                const SizedBox(height: 24),
                _entrySection(data),
              ],
            ],
          ),
        ),
        if (_busy)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black45,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    if (_busyText != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _busyText!,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
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
          onPressed: _busy ? null : () => _moveDay(-1),
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
          onPressed: _day == _today || _busy ? null : () => _moveDay(1),
        ),
      ],
    );
  }

  Widget _loginBox() => _messageBox(
    '일기는 관리자만 볼 수 있어요.\n관리자 비밀번호로 로그인해 주세요',
    '관리자 로그인',
    _login,
    icon: Icons.lock_outline,
  );

  Widget _messageBox(
    String text,
    String action,
    VoidCallback onTap, {
    IconData icon = Icons.error_outline,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Column(
      children: [
        Icon(icon, color: Colors.white38, size: 40),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(backgroundColor: _color),
          child: Text(action),
        ),
      ],
    ),
  );

  Widget _sectionTitle(String text, {Widget? trailing}) => Row(
    children: [
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      ?trailing,
    ],
  );

  Widget _notesSection(DiaryDay data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          '메모 ${data.notes.length}개',
          trailing: TextButton.icon(
            onPressed: _busy ? null : _addNote,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('메모 추가'),
            style: TextButton.styleFrom(foregroundColor: _color),
          ),
        ),
        const SizedBox(height: 6),
        if (data.notes.isEmpty)
          _hint(
            'claude.ai 인간 프로젝트에서 나눈 대화나 오늘 생각을 메모로 남겨 두면 '
            '밤 10시에 일기 초안으로 엮어 드려요.',
          )
        else
          for (final n in data.notes) _noteCard(n),
        if (data.recordKinds.isNotEmpty) ...[
          const SizedBox(height: 6),
          _hint('초안에 함께 넣는 기록: ${data.recordKinds.join(' · ')}'),
        ],
      ],
    );
  }

  Widget _noteCard(DiaryNote n) {
    final t = n.createdAt;
    final time = t == null
        ? ''
        : ' · ${t.hour.toString().padLeft(2, '0')}:'
              '${t.minute.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: _color, width: 3)),
      ),
      // ExpansionTile 이 카드 배경 위에 물결 효과를 그리도록 투명 Material 을 둠
      child: Material(
        type: MaterialType.transparency,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.only(left: 14, right: 4),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            iconColor: Colors.white54,
            collapsedIconColor: Colors.white54,
            title: Text(
              n.content
                  .split('\n')
                  .firstWhere((l) => l.trim().isNotEmpty, orElse: () => ''),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            subtitle: Text(
              '${n.sourceLabel}$time',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  n.content,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    height: 1.5,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _busy ? null : () => _deleteNote(n),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('지우기'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _entrySection(DiaryDay data) {
    final diary = data.diary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('일기'),
        const SizedBox(height: 8),
        if (diary == null) ...[
          _hint(
            _day == _today
                ? '오늘 밤 10시에 메모로 초안을 만들어요. 지금 바로 만들 수도 있어요.'
                : '아직 초안이 없어요.',
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed:
                  _busy || (data.notes.isEmpty && data.recordKinds.isEmpty)
                  ? null
                  : () => _generate(again: false),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('지금 초안 만들기'),
              style: FilledButton.styleFrom(
                backgroundColor: _color,
                minimumSize: const Size(0, 48),
              ),
            ),
          ),
        ] else
          _entryCard(diary),
        if (data.book != null) ...[
          const SizedBox(height: 24),
          _sectionTitle('독서 기록'),
          const SizedBox(height: 8),
          _entryCard(data.book!),
        ],
      ],
    );
  }

  Widget _entryCard(DiaryEntry e) {
    final status = e.isPublished
        ? '블로그에 게시함'
        : e.edited
        ? '초안 · 직접 고침'
        : '초안';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: e.isPublished
              ? _color.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                e.isPublished ? Icons.check_circle : Icons.edit_note,
                size: 16,
                color: e.isPublished ? _color : Colors.white54,
              ),
              const SizedBox(width: 6),
              Text(
                status,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            e.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (e.warnings.isNotEmpty && !e.isPublished) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '게시 전에 확인해 주세요',
                    style: TextStyle(
                      color: _amber,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  for (final w in e.warnings)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '· $w',
                        style: const TextStyle(color: _amber, fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          SelectableText(
            e.content,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              height: 1.6,
            ),
          ),
          if (!e.isPublished) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _edit(e),
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('고치기'),
                  style: _outlined(),
                ),
                if (!e.isBook)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _generate(again: true),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('다시 만들기'),
                    style: _outlined(),
                  ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _discard(e),
                  style: _outlined(color: Colors.redAccent),
                  child: const Text('버리기'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _publish(e),
                icon: const Icon(Icons.publish),
                label: const Text('블로그에 게시'),
                style: FilledButton.styleFrom(
                  backgroundColor: _color,
                  minimumSize: const Size(0, 48),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  ButtonStyle _outlined({Color color = Colors.white}) =>
      OutlinedButton.styleFrom(
        foregroundColor: color,
        side: const BorderSide(color: Colors.white24),
      );

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.5),
        fontSize: 13,
        height: 1.5,
      ),
    ),
  );

  Future<bool> _confirm(String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

// 메모 쓰기: 붙여넣기 버튼 + 출처(Claude 앱 대화 / 직접 쓴 메모). 저장하면 (내용, source)
class _NoteSheet extends StatefulWidget {
  const _NoteSheet();

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  final _text = TextEditingController();
  String _source = 'app';

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text?.trim();
    if (t == null || t.isEmpty) return;
    _text.text = _text.text.trim().isEmpty ? t : '${_text.text}\n\n$t';
  }

  @override
  Widget build(BuildContext context) {
    final color = Persona.human.color;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '메모 추가',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste, size: 18),
                  label: const Text('붙여넣기'),
                  style: TextButton.styleFrom(foregroundColor: color),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final (value, label) in const [
                  ('app', 'Claude 앱 대화'),
                  ('manual', '직접 쓴 메모'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _source == value,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _source = value),
                    selectedColor: color.withValues(alpha: 0.35),
                    labelStyle: TextStyle(
                      color: _source == value ? Colors.white : Colors.white70,
                    ),
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _text,
              minLines: 6,
              maxLines: 12,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(color: Colors.white, height: 1.5),
              cursorColor: color,
              decoration: InputDecoration(
                hintText:
                    '오늘 있었던 일, 생각, 떠오른 질문...\n'
                    'claude.ai 에서 정리한 내용을 붙여넣어도 돼요',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                final t = _text.text.trim();
                if (t.isEmpty) return;
                Navigator.pop(context, (t, _source));
              },
              style: FilledButton.styleFrom(
                backgroundColor: color,
                minimumSize: const Size(0, 48),
              ),
              child: const Text('메모 저장'),
            ),
          ],
        ),
      ),
    );
  }
}

// 초안 고치기 (전체 화면). 저장하면 (제목, 내용)
class _EntryEditor extends StatefulWidget {
  const _EntryEditor({required this.entry});

  final DiaryEntry entry;

  @override
  State<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<_EntryEditor> {
  late final _title = TextEditingController(text: widget.entry.title);
  late final _body = TextEditingController(text: widget.entry.content);

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Persona.human.color;
    InputDecoration deco(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
    return Scaffold(
      backgroundColor: const Color(0xFF15122B),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(widget.entry.isBook ? '독서 기록 고치기' : '일기 고치기'),
        actions: [
          TextButton(
            onPressed: () {
              final t = _title.text.trim();
              final b = _body.text.trim();
              if (t.isEmpty || b.isEmpty) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('제목과 내용을 써 주세요')));
                return;
              }
              Navigator.pop(context, (t, b));
            },
            child: Text('저장', style: TextStyle(color: color, fontSize: 16)),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            TextField(
              controller: _title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
              cursorColor: color,
              decoration: deco('제목'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _body,
              minLines: 16,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(color: Colors.white, height: 1.6),
              cursorColor: color,
              decoration: deco('내용'),
            ),
          ],
        ),
      ),
    );
  }
}

// 게시: 소메뉴(일기는 기본값 있음) + 공개 여부. 확인하면 (subId, 공개)
class _PublishSheet extends StatefulWidget {
  const _PublishSheet({required this.entry, required this.menus});

  final DiaryEntry entry;
  final DiarySubMenus menus;

  @override
  State<_PublishSheet> createState() => _PublishSheetState();
}

class _PublishSheetState extends State<_PublishSheet> {
  late int? _subId = widget.entry.isBook ? null : widget.menus.diaryDefault;
  bool _public = false; // 회사 이야기가 섞일 수 있어 기본은 비공개

  @override
  Widget build(BuildContext context) {
    final color = Persona.human.color;
    final subs = widget.menus.subs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '블로그에 게시',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: subs.any((s) => s.id == _subId) ? _subId : null,
              dropdownColor: const Color(0xFF2A2550),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: '올릴 메뉴',
                labelStyle: const TextStyle(color: Colors.white60),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              items: [
                for (final s in subs)
                  DropdownMenuItem(value: s.id, child: Text(s.label)),
              ],
              onChanged: (v) => setState(() => _subId = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _public,
              onChanged: (v) => setState(() => _public = v),
              activeThumbColor: color,
              title: const Text('공개', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                _public ? '웹 블로그 방문자도 볼 수 있어요' : '나만 볼 수 있어요',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _subId == null
                  ? null
                  : () => Navigator.pop(context, (_subId, _public)),
              style: FilledButton.styleFrom(
                backgroundColor: color,
                minimumSize: const Size(0, 48),
              ),
              child: Text(_public ? '공개로 게시' : '비공개로 게시'),
            ),
          ],
        ),
      ),
    );
  }
}
