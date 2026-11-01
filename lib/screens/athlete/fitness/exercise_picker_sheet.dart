import 'package:flutter/material.dart';

import '../../../models/athlete_section.dart';
import '../../../models/workout.dart';
import '../../../services/api_client.dart';

// 운동 종목 고르기: 부위 칩 + 이름 검색. 고른 종목을 돌려주고, 닫으면 null
Future<ExerciseItem?> showExercisePicker(
  BuildContext context, {
  required Future<(List<ExerciseCategory>, List<ExerciseItem>)> catalog,
}) {
  return showModalBottomSheet<ExerciseItem>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFF211E36),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) =>
          _PickerBody(catalog: catalog, controller: controller),
    ),
  );
}

class _PickerBody extends StatefulWidget {
  const _PickerBody({required this.catalog, required this.controller});

  final Future<(List<ExerciseCategory>, List<ExerciseItem>)> catalog;
  final ScrollController controller;

  @override
  State<_PickerBody> createState() => _PickerBodyState();
}

class _PickerBodyState extends State<_PickerBody> {
  static final _color = AthleteSection.fitness.color;

  int? _categoryId; // null 이면 전체
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: widget.catalog,
      builder: (context, snap) {
        if (snap.hasError) {
          final e = snap.error;
          return Center(
            child: Text(e is ApiException ? e.message : '종목을 불러오지 못했어요'),
          );
        }
        final data = snap.data;
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final (categories, items) = data;
        final shown = items
            .where(
              (i) =>
                  (_categoryId == null || i.categoryId == _categoryId) &&
                  i.matches(_query),
            )
            .toList();
        final names = {for (final c in categories) c.id: c.name};

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: '운동 이름 검색',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final (id, name) in [
                    (null, '전체'),
                    for (final c in categories) (c.id, c.name),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(name),
                        selected: _categoryId == id,
                        selectedColor: _color.withValues(alpha: 0.3),
                        onSelected: (_) => setState(() => _categoryId = id),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? const Center(child: Text('맞는 운동이 없어요'))
                  : ListView.builder(
                      controller: widget.controller,
                      padding: EdgeInsets.only(
                        bottom: 16 + MediaQuery.viewPaddingOf(context).bottom,
                      ),
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final item = shown[i];
                        return ListTile(
                          title: Text(item.nameKo),
                          subtitle: Text(
                            [
                              names[item.categoryId],
                              item.equipmentLabel,
                              item.nameEn,
                            ].nonNulls.join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.pop(context, item),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
