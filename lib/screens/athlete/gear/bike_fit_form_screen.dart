import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/bike.dart';
import '../../../services/api_client.dart';
import '../../../services/bike_api.dart';
import '../../../utils/format.dart';
import '../../../widgets/admin_login_dialog.dart';
import '../../../widgets/bottom_action_bar.dart';

// 피팅 기록 추가: 피팅받는 자리에서 바로 적도록 직전 피팅 값을 미리 채워 두고 바뀐 것만 고침.
// 저장은 관리자만 (지문 로그인)
class BikeFitFormScreen extends StatefulWidget {
  const BikeFitFormScreen({
    super.key,
    required this.bike,
    required this.api,
    required this.color,
    this.previous,
    this.now,
  });

  final Bike bike;
  final BikeApi api;
  final Color color;
  final BikeFit? previous; // 미리 채울 직전 피팅
  final DateTime? now; // 테스트에서 '오늘' 고정용

  @override
  State<BikeFitFormScreen> createState() => _BikeFitFormScreenState();
}

// (서버 키, 이름, 단위) — 숫자 칸
const _numberFields = [
  ('saddleHeightMm', '안장 높이', 'mm'),
  ('saddleSetbackMm', '안장 셋백', 'mm'),
  ('saddleTiltDeg', '안장 각도', '°'),
  ('reachMm', '리치', 'mm'),
  ('dropMm', '드롭', 'mm'),
  ('stemLengthMm', '스템 길이', 'mm'),
  ('stemAngleDeg', '스템 각도', '°'),
  ('spacerMm', '스페이서', 'mm'),
  ('handlebarWidthMm', '핸들바 폭', 'mm'),
  ('crankLengthMm', '크랭크 길이', 'mm'),
];

// (서버 키, 이름) — 글자 칸
const _textFields = [
  ('saddleModel', '안장 모델'),
  ('cleatLeft', '클릿 (왼쪽)'),
  ('cleatRight', '클릿 (오른쪽)'),
];

class _BikeFitFormScreenState extends State<BikeFitFormScreen> {
  late DateTime _date = _dayOf(widget.now ?? DateTime.now());
  late final _fitter = TextEditingController(
    text: widget.previous?.fitter ?? '',
  );
  late final _notes = TextEditingController();
  late final Map<String, TextEditingController> _fields = {
    for (final (key, _, _) in _numberFields)
      key: TextEditingController(text: _prefill(key)),
    for (final (key, _) in _textFields)
      key: TextEditingController(text: _prefill(key)),
  };
  bool _saving = false;

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  String _prefill(String key) => switch (widget.previous?.raw[key]) {
    final num v => v == v.roundToDouble() ? '${v.toInt()}' : '$v',
    final String v => v,
    _ => '',
  };

  @override
  void dispose() {
    _fitter.dispose();
    _notes.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime(_date.year + 1, 12, 31),
    );
    if (picked != null) setState(() => _date = picked);
  }

  String? _text(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  Map<String, Object?> _body() => {
    'fitDate':
        '${_date.year}-${_date.month.toString().padLeft(2, '0')}-'
        '${_date.day.toString().padLeft(2, '0')}',
    'fitter': _text(_fitter),
    for (final (key, _, _) in _numberFields)
      key: double.tryParse(_fields[key]!.text.trim()),
    for (final (key, _) in _textFields) key: _text(_fields[key]!),
    'notes': _text(_notes),
  };

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final body = _body();
    setState(() => _saving = true);
    try {
      try {
        await widget.api.createFit(widget.bike.id, body);
      } on AdminRequiredException {
        // 저장은 관리자만. 지문(또는 비밀번호) 로그인 후 한 번 더
        if (!mounted ||
            !await loginAdminWithDialog(context, widget.api.loginAdmin)) {
          return;
        }
        await widget.api.createFit(widget.bike.id, body);
      }
      messenger.showSnackBar(const SnackBar(content: Text('피팅을 저장했어요')));
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
    final prev = widget.previous;

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
      for (final (key, label, unit) in _numberFields)
        TextField(
          controller: _fields[key],
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true, // 스템 각도 -6° 같은 음수
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d{0,1}')),
          ],
          decoration: deco(label, suffix: unit),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text('피팅 추가 · ${widget.bike.name}'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.event, color: widget.color),
            title: const Text('피팅 날짜'),
            trailing: Text(
              formatDate(_date),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            onTap: _pickDate,
          ),
          TextField(controller: _fitter, decoration: deco('피팅 업체 · 피터')),
          if (prev != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '${formatDate(prev.date)} 피팅 값을 미리 채웠어요. 바뀐 것만 고치세요',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
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
          for (final (key, label) in _textFields)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: _fields[key],
                decoration: deco(label),
              ),
            ),
          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 5,
            decoration: deco('메모 (바꾼 이유, 느낌)'),
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
