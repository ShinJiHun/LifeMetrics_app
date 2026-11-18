import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/persona.dart';
import '../../services/api_client.dart';
import '../../services/diary_api.dart';

// 인간 페르소나: 하루 일기 쓰기.
// claude.ai '인간' 프로젝트에서 정리한 일기를 붙여넣거나 직접 써서 날짜별로 저장
class DiaryScreen extends StatefulWidget {
  const DiaryScreen({super.key, this.api, this.now});

  final DiaryApi? api;
  final DateTime? now; // 테스트에서 '오늘' 고정용

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  static final _color = Persona.human.color;

  late final DiaryApi _api = widget.api ?? DiaryApi();
  late final DateTime _today = _dateOnly(widget.now ?? DateTime.now());
  late DateTime _day = _today;

  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _isPublic = false;

  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  Diary? _saved; // 서버에 있는 그날 일기
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _title.addListener(_markDirty);
    _body.addListener(_markDirty);
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty && !_loading) setState(() => _dirty = true);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    Diary? d;
    String? error;
    try {
      d = await _api.fetch(_day);
    } on ApiException catch (e) {
      error = e.message;
    }
    if (!mounted) return;
    _title.text = d?.title ?? '';
    _body.text = d?.body ?? '';
    setState(() {
      _saved = d;
      _isPublic = d?.isPublic ?? false;
      _loadError = error;
      _loading = false;
      _dirty = false;
    });
  }

  Future<void> _moveDay(int delta) async {
    final next = _day.add(Duration(days: delta));
    if (next.isAfter(_today)) return;
    if (_dirty && !await _confirm('저장하지 않은 내용이 있어요. 다른 날로 이동할까요?')) {
      return;
    }
    setState(() => _day = next);
    await _load();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      _toast('클립보드가 비어 있어요');
      return;
    }
    if (_body.text.trim().isNotEmpty &&
        !await _confirm('지금 쓴 내용을 클립보드 내용으로 바꿀까요?')) {
      return;
    }
    _body.text = text;
  }

  Future<void> _save() async {
    if (_body.text.trim().isEmpty) {
      _toast('일기 내용을 써 주세요');
      return;
    }
    setState(() => _saving = true);
    try {
      final d = await _api.save(
        _day,
        body: _body.text,
        title: _title.text.trim().isEmpty ? null : _title.text.trim(),
        isPublic: _isPublic,
      );
      if (!mounted) return;
      _title.text = d.title ?? '';
      setState(() {
        _saved = d;
        _dirty = false;
      });
      _toast('저장했어요');
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (!await _confirm('이날 일기를 지울까요? 되돌릴 수 없어요.')) return;
    setState(() => _saving = true);
    try {
      await _api.delete(_day);
      if (!mounted) return;
      _title.clear();
      _body.clear();
      setState(() {
        _saved = null;
        _isPublic = false;
        _dirty = false;
      });
      _toast('지웠어요');
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        _dateBar(),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_loadError != null)
          _errorBox()
        else
          ..._editor(),
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
          onPressed: _saving ? null : () => _moveDay(-1),
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
          onPressed: _day == _today || _saving ? null : () => _moveDay(1),
        ),
      ],
    );
  }

  List<Widget> _editor() {
    final status = _saved == null
        ? '아직 이날 일기가 없어요'
        : _dirty
        ? '고친 내용이 아직 저장되지 않았어요'
        : '저장됨';
    return [
      Row(
        children: [
          Icon(
            _saved != null && !_dirty ? Icons.check_circle : Icons.edit_note,
            size: 16,
            color: _saved != null && !_dirty ? _color : Colors.white54,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              status,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ),
          TextButton.icon(
            onPressed: _saving ? null : _paste,
            icon: const Icon(Icons.content_paste, size: 18),
            label: const Text('붙여넣기'),
            style: TextButton.styleFrom(foregroundColor: _color),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _field(_title, hint: '제목 (비우면 날짜로)', maxLines: 1),
      const SizedBox(height: 10),
      _field(
        _body,
        hint: '오늘 있었던 일, 생각, 떠오른 질문...\n'
            'claude.ai 인간 프로젝트에서 정리한 일기를 붙여넣어도 돼요',
        minLines: 12,
        maxLines: null,
      ),
      const SizedBox(height: 6),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _isPublic,
        onChanged: _saving
            ? null
            : (v) => setState(() {
                _isPublic = v;
                _dirty = true;
              }),
        activeThumbColor: _color,
        title: const Text('블로그에 공개', style: TextStyle(color: Colors.white)),
        subtitle: Text(
          _isPublic ? '웹 블로그 방문자도 볼 수 있어요' : '나만 볼 수 있어요 (회사 이야기는 비공개 권장)',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          if (_saved != null) ...[
            OutlinedButton(
              onPressed: _saving ? null : _delete,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.white24),
                minimumSize: const Size(0, 48),
              ),
              child: const Text('삭제'),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(_saved == null ? '일기 저장' : '고친 내용 저장'),
              style: FilledButton.styleFrom(
                backgroundColor: _color,
                minimumSize: const Size(0, 48),
              ),
            ),
          ),
        ],
      ),
    ];
  }

  Widget _field(
    TextEditingController c, {
    required String hint,
    int? minLines,
    int? maxLines,
  }) {
    return TextField(
      controller: c,
      enabled: !_saving,
      minLines: minLines,
      maxLines: maxLines,
      keyboardType: maxLines == 1 ? TextInputType.text : TextInputType.multiline,
      style: const TextStyle(color: Colors.white, height: 1.5),
      cursorColor: _color,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _color),
        ),
      ),
    );
  }

  Widget _errorBox() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Column(
      children: [
        Text(_loadError!, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _load, child: const Text('다시 시도')),
      ],
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
