import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/health_checkup.dart';
import '../../../services/api_client.dart';
import '../../../services/health_checkup_api.dart';
import '../../../utils/format.dart';
import '../../../widgets/admin_login_dialog.dart';
import '../../../widgets/bottom_action_bar.dart';

// 건강검진 저장 전 검토: AI 가 PDF 에서 뽑은 값(또는 빈 값)을 보여주고 고친 뒤 저장.
// 화면에는 날짜 · 기관 · 판정과 주요 수치만 두고, 나머지 항목(시력 · 청력 · 추가 검사 · 원문 등)은
// AI 결과 그대로 함께 저장
class HealthCheckupFormScreen extends StatefulWidget {
  const HealthCheckupFormScreen({
    super.key,
    required this.api,
    required this.color,
    this.initial = const {},
    this.fromPdf = false,
  });

  final HealthCheckupApi api;
  final Color color;
  final Map<String, dynamic> initial;
  final bool fromPdf;

  @override
  State<HealthCheckupFormScreen> createState() =>
      _HealthCheckupFormScreenState();
}

// (서버 키, 이름) — 글자 칸
const _textFields = [
  ('checkupPlace', '검진 기관'),
  ('overallJudgment', '종합판정'),
  ('suspectedDisease', '의심 질환'),
  ('lifestyleAdvice', '생활습관 권고'),
];

class _HealthCheckupFormScreenState extends State<HealthCheckupFormScreen> {
  DateTime? _date;
  late final Map<String, TextEditingController> _texts = {
    for (final (key, _) in _textFields)
      key: TextEditingController(text: _string(widget.initial[key])),
  };
  late final Map<String, TextEditingController> _numbers = {
    for (final m in CheckupMetric.all)
      m.key: TextEditingController(text: _string(widget.initial[m.key])),
  };
  bool _saving = false;

  static String _string(Object? v) => switch (v) {
    final num n when n == n.roundToDouble() => '${n.toInt()}',
    final num n => '$n',
    final String s => s,
    _ => '',
  };

  @override
  void initState() {
    super.initState();
    _date = switch (widget.initial['checkupDate']) {
      final String s => DateTime.tryParse(s),
      _ => null,
    };
  }

  @override
  void dispose() {
    for (final c in [..._texts.values, ..._numbers.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Map<String, dynamic> _body() {
    String? text(TextEditingController c) {
      final t = c.text.trim();
      return t.isEmpty ? null : t;
    }

    final d = _date!;
    return {
      ...widget.initial,
      'id': null, // 새로 저장
      'checkupDate':
          '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}',
      for (final e in _texts.entries) e.key: text(e.value),
      for (final e in _numbers.entries)
        e.key: double.tryParse(e.value.text.trim()),
    };
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_date == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('검진 날짜를 골라 주세요')),
      );
      return;
    }
    final body = _body();
    setState(() => _saving = true);
    try {
      try {
        await widget.api.create(body);
      } on AdminRequiredException {
        if (!mounted ||
            !await loginAdminWithDialog(context, widget.api.loginAdmin)) {
          return;
        }
        await widget.api.create(body);
      }
      messenger.showSnackBar(const SnackBar(content: Text('검진을 저장했어요')));
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.55);
    InputDecoration deco(String label, {String? suffix}) => InputDecoration(
      labelText: label,
      suffixText: suffix,
      isDense: true,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
    );

    final numberInputs = [
      for (final m in CheckupMetric.all)
        TextField(
          controller: _numbers[m.key],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          ],
          decoration: deco(m.label, suffix: m.unit.isEmpty ? null : m.unit),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(widget.fromPdf ? '검진 확인 후 저장' : '검진 직접 입력'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (widget.fromPdf)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'AI 가 PDF 에서 읽은 값이에요. 결과통보서와 다른 곳만 고쳐 주세요. '
                '화면에 없는 항목(시력 · 청력 · 추가 검사 등)도 함께 저장돼요',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.event, color: widget.color),
            title: const Text('검진 날짜'),
            trailing: Text(
              _date == null ? '골라 주세요' : formatDate(_date!),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: _date == null ? Colors.amber.shade200 : null,
              ),
            ),
            onTap: _pickDate,
          ),
          for (final (key, label) in _textFields)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: _texts[key],
                maxLines: key == 'lifestyleAdvice' ? 3 : 1,
                decoration: deco(label),
              ),
            ),
          const SizedBox(height: 6),
          Text('주요 수치', style: TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 8),
          for (var i = 0; i < numberInputs.length; i += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(child: numberInputs[i]),
                  const SizedBox(width: 10),
                  Expanded(
                    child: i + 1 < numberInputs.length
                        ? numberInputs[i + 1]
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        child: FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: widget.color,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: _saving
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text(
                  '저장',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
        ),
      ),
    );
  }
}
