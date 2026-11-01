import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/athlete_section.dart';
import '../../../models/workout.dart';
import '../../../services/api_client.dart';
import '../../../services/fitness_api.dart';
import '../../../utils/format.dart';
import '../../../widgets/admin_login_dialog.dart';
import 'exercise_picker_sheet.dart';

// 피트니스 입력: 날짜 · PT 여부 → 운동 종목 고르기 → 세트별 무게 × 횟수 → 저장
class WorkoutInputScreen extends StatefulWidget {
  const WorkoutInputScreen({super.key, this.api, this.now});

  final FitnessApi? api;
  final DateTime? now; // 테스트에서 '오늘' 고정용

  @override
  State<WorkoutInputScreen> createState() => _WorkoutInputScreenState();
}

class _WorkoutInputScreenState extends State<WorkoutInputScreen> {
  static final _color = AthleteSection.fitness.color;

  late final FitnessApi _api = widget.api ?? FitnessApi();
  late final DateTime _today = _dayOf(widget.now ?? DateTime.now());
  late DateTime _date = _today;
  bool _isPT = false;
  final _drafts = <_DraftExercise>[];
  bool _saving = false;

  // 종목 목록은 처음 고를 때 한 번만 받아 둠
  Future<(List<ExerciseCategory>, List<ExerciseItem>)>? _catalog;

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void dispose() {
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: _today,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _addExercise() async {
    final catalog = _catalog ??= () async {
      try {
        return (await _api.fetchCategories(), await _api.fetchItems());
      } catch (_) {
        _catalog = null; // 다음에 열 때 다시 받게
        rethrow;
      }
    }();
    final item = await showExercisePicker(context, catalog: catalog);
    if (item == null || !mounted) return;
    setState(() => _drafts.add(_DraftExercise(item)));
  }

  // 모든 세트에 횟수가 있어야 저장. 무게를 비우면 맨몸으로 보고 0kg
  List<WorkoutExercise>? _validExercises() {
    final exercises = <WorkoutExercise>[];
    for (final d in _drafts) {
      final sets = <WorkoutSet>[];
      for (final (i, s) in d.sets.indexed) {
        final reps = int.tryParse(s.reps.text);
        if (reps == null || reps <= 0) return null;
        sets.add(
          WorkoutSet(
            setNumber: i + 1,
            weight: double.tryParse(s.weight.text) ?? 0,
            reps: reps,
          ),
        );
      }
      if (sets.isEmpty) return null;
      exercises.add(WorkoutExercise(exerciseItemId: d.item.id, sets: sets));
    }
    return exercises;
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final exercises = _validExercises();
    if (exercises == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('모든 세트에 횟수를 입력해 주세요')),
      );
      return;
    }

    Future<void> log() =>
        _api.logWorkout(date: _date, isPT: _isPT, exercises: exercises);

    setState(() => _saving = true);
    try {
      try {
        await log();
      } on AdminRequiredException {
        // 저장은 관리자만 가능. 비밀번호로 로그인한 뒤 한 번 더 보냄
        if (!mounted || !await loginAdminWithDialog(context, _api.loginAdmin)) {
          return;
        }
        await log();
      }
      messenger.showSnackBar(const SnackBar(content: Text('운동을 저장했어요')));
      if (!mounted) return;
      setState(() {
        for (final d in _drafts) {
          d.dispose();
        }
        _drafts.clear();
      });
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('운동 입력'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Material(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.event, color: _color),
                  title: const Text('날짜'),
                  trailing: Text(
                    _date == _today
                        ? '오늘 (${formatDate(_date)})'
                        : formatDate(_date),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: _pickDate,
                ),
                SwitchListTile(
                  secondary: Icon(Icons.person, color: _color),
                  title: const Text('PT 수업'),
                  value: _isPT,
                  activeThumbColor: _color,
                  onChanged: (v) => setState(() => _isPT = v),
                ),
              ],
            ),
          ),
          for (final (i, d) in _drafts.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _DraftCard(
                key: ObjectKey(d),
                draft: d,
                color: _color,
                onChanged: () => setState(() {}),
                onRemove: () => setState(() => _drafts.removeAt(i).dispose()),
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _addExercise,
            style: OutlinedButton.styleFrom(
              foregroundColor: _color,
              side: BorderSide(color: _color.withValues(alpha: 0.6)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.add),
            label: const Text('운동 추가'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          onPressed: _drafts.isEmpty || _saving ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: _color,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: _saving
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  _drafts.isEmpty ? '운동을 추가해 주세요' : '저장',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}

// 입력 중인 세트 하나. 무게/횟수 입력칸
class _DraftSet {
  _DraftSet({String weight = '', String reps = ''})
    : weight = TextEditingController(text: weight),
      reps = TextEditingController(text: reps);

  final TextEditingController weight;
  final TextEditingController reps;

  void dispose() {
    weight.dispose();
    reps.dispose();
  }
}

class _DraftExercise {
  _DraftExercise(this.item);

  final ExerciseItem item;
  final sets = [_DraftSet()];

  // 새 세트는 직전 세트 값으로 채워 둠
  void addSet() => sets.add(
    _DraftSet(
      weight: sets.lastOrNull?.weight.text ?? '',
      reps: sets.lastOrNull?.reps.text ?? '',
    ),
  );

  void dispose() {
    for (final s in sets) {
      s.dispose();
    }
  }
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({
    super.key,
    required this.draft,
    required this.color,
    required this.onChanged,
    required this.onRemove,
  });

  final _DraftExercise draft;
  final Color color;
  final VoidCallback onChanged; // 세트 추가/삭제 후 다시 그리기
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.55);
    final item = draft.item;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.nameKo,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (item.equipmentLabel != null)
                      Text(
                        item.equipmentLabel!,
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '운동 빼기',
                onPressed: onRemove,
                icon: Icon(Icons.close, color: muted),
              ),
            ],
          ),
          for (final (i, s) in draft.sets.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${i + 1}세트',
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  ),
                  Expanded(
                    child: _NumberField(
                      controller: s.weight,
                      suffix: 'kg',
                      decimal: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _NumberField(controller: s.reps, suffix: '회'),
                  ),
                  SizedBox(
                    width: 40,
                    child: draft.sets.length > 1
                        ? IconButton(
                            tooltip: '세트 빼기',
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              draft.sets.removeAt(i).dispose();
                              onChanged();
                            },
                            icon: Icon(
                              Icons.remove_circle_outline,
                              color: muted,
                              size: 20,
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          TextButton.icon(
            onPressed: () {
              draft.addSet();
              onChanged();
            },
            style: TextButton.styleFrom(foregroundColor: color),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('세트 추가'),
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.suffix,
    this.decimal = false,
  });

  final TextEditingController controller;
  final String suffix;
  final bool decimal; // 무게는 소수점 허용 (2.5kg 원판 등)

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          decimal ? RegExp(r'^\d*\.?\d{0,2}') : RegExp(r'\d'),
        ),
      ],
      textAlign: TextAlign.end,
      decoration: InputDecoration(
        isDense: true,
        suffixText: suffix,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
