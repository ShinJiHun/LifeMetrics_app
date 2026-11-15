import 'dart:math';

import '../models/workout.dart';

// 오늘 할 부위. 서버 카테고리 id 묶음 (팔은 팔/삼두/이두 모두)
enum BodyPart {
  chest('가슴', {1}),
  back('등', {2}),
  shoulder('어깨', {3}),
  arms('팔', {4, 9, 10}),
  legs('하체', {5}),
  abs('복근', {6}),
  cardio('유산소', {7});

  const BodyPart(this.label, this.categoryIds);

  final String label;
  final Set<int> categoryIds;
}

// 운동 목표별 세트 · 횟수 범위
enum TrainingGoal {
  hypertrophy(
    '근비대',
    sets: 4,
    repsMin: 8,
    repsMax: 12,
    restSec: 90,
    cardioMin: 20,
  ),
  strength('근력', sets: 5, repsMin: 4, repsMax: 6, restSec: 180, cardioMin: 15),
  cut('감량', sets: 3, repsMin: 10, repsMax: 15, restSec: 60, cardioMin: 30),
  endurance(
    '근지구력',
    sets: 3,
    repsMin: 15,
    repsMax: 20,
    restSec: 45,
    cardioMin: 30,
  );

  const TrainingGoal(
    this.label, {
    required this.sets,
    required this.repsMin,
    required this.repsMax,
    required this.restSec,
    required this.cardioMin,
  });

  final String label;
  final int sets;
  final int repsMin;
  final int repsMax;
  final int restSec;
  final int cardioMin; // 유산소 추천 시간

  int get targetReps => (repsMin + repsMax) ~/ 2;
}

// 한 종목의 최근 기록 요약
class ExerciseRecord {
  const ExerciseRecord({
    required this.lastDate,
    required this.topWeight,
    required this.topReps,
    required this.times,
  });

  final DateTime lastDate;
  final double topWeight; // 가장 최근 세션의 가장 무거운 세트
  final int topReps;
  final int times; // 기간 안에 한 횟수
}

// 추천 1개
class Recommendation {
  const Recommendation({
    required this.item,
    required this.part,
    required this.sets,
    required this.repsMin,
    required this.repsMax,
    required this.reason,
    this.weight,
    this.minutes,
    this.restSec,
  });

  final ExerciseItem item;
  final BodyPart part;
  final int sets;
  final int repsMin;
  final int repsMax;
  final double? weight; // null 이면 맨몸이거나 처음이라 무게를 정하지 못함
  final int? minutes; // 유산소면 시간, 세트/횟수 대신
  final int? restSec;
  final String reason; // 왜 이 무게인지

  bool get isCardio => minutes != null;
  int get targetReps => (repsMin + repsMax) ~/ 2;
}

class WorkoutRecommender {
  // 세션들(최신순 아니어도 됨)을 종목별 최근 기록으로
  static Map<int, ExerciseRecord> summarize(List<WorkoutSession> sessions) {
    final sorted = [...sessions]..sort((a, b) => b.date.compareTo(a.date));
    final out = <int, ExerciseRecord>{};
    final times = <int, int>{};
    for (final s in sorted) {
      for (final e in s.exercises) {
        times[e.exerciseItemId] = (times[e.exerciseItemId] ?? 0) + 1;
        if (out.containsKey(e.exerciseItemId)) continue; // 가장 최근 것만
        WorkoutSet? top;
        for (final set in e.sets) {
          if (set.reps == null || set.reps! <= 0) continue;
          final w = set.weight ?? 0;
          final tw = top?.weight ?? 0;
          if (top == null || w > tw || (w == tw && set.reps! > top.reps!)) {
            top = set;
          }
        }
        if (top == null) continue;
        out[e.exerciseItemId] = ExerciseRecord(
          lastDate: s.date,
          topWeight: top.weight ?? 0,
          topReps: top.reps!,
          times: 0,
        );
      }
    }
    return {
      for (final MapEntry(:key, :value) in out.entries)
        key: ExerciseRecord(
          lastDate: value.lastDate,
          topWeight: value.topWeight,
          topReps: value.topReps,
          times: times[key] ?? 1,
        ),
    };
  }

  // 부위가 하나면 5개, 둘이면 3개씩, 셋 이상이면 2개씩. 유산소는 1개
  static int countFor(BodyPart part, int partCount) {
    if (part == BodyPart.cardio) return 1;
    return switch (partCount) {
      1 => 5,
      2 => 3,
      _ => 2,
    };
  }

  /// GIF 가 있는 종목만 추천한다. [shuffle] 이 0 이면 점수 순서 그대로,
  /// 다른 값이면 그 값을 시드로 조금씩 섞어 '다른 운동으로' 를 만든다.
  static List<Recommendation> recommend({
    required List<BodyPart> parts,
    required TrainingGoal goal,
    required List<ExerciseItem> items,
    Map<int, ExerciseRecord> records = const {},
    int shuffle = 0,
  }) {
    final rand = Random(shuffle);
    final result = <Recommendation>[];
    final usedGifs = <String>{}; // 같은 GIF 를 쓰는 종목(이름만 다른 중복)은 하나만

    for (final part in parts) {
      final candidates = items
          .where((i) => i.hasGif && part.categoryIds.contains(i.categoryId))
          .toList();
      final scores = {
        for (final i in candidates)
          i.id:
              _score(i, records[i.id]) +
              (shuffle == 0 ? 0 : rand.nextDouble() * 4),
      };
      candidates.sort((a, b) => scores[b.id]!.compareTo(scores[a.id]!));

      final picked = <ExerciseItem>[];
      for (final i in candidates) {
        if (picked.length >= countFor(part, parts.length)) break;
        if (!usedGifs.add(i.gifUrl!)) continue;
        picked.add(i);
      }
      // 복합 · 프리웨이트를 먼저, 고립 · 맨몸을 뒤로
      picked.sort((a, b) => _equipOrder(a).compareTo(_equipOrder(b)));
      result.addAll(picked.map((i) => _plan(i, part, goal, records[i.id])));
    }
    return result;
  }

  static int _equipOrder(ExerciseItem i) => switch (i.equipmentType) {
    'FREE_WEIGHT' => 0,
    'MACHINE' => 1,
    'CABLE' => 2,
    _ => 3,
  };

  // 해 본 운동을 우선, 그다음 프리웨이트 > 머신 > 케이블 > 맨몸
  static double _score(ExerciseItem i, ExerciseRecord? r) {
    final equip = switch (i.equipmentType) {
      'FREE_WEIGHT' => 3.0,
      'MACHINE' => 2.5,
      'CABLE' => 2.0,
      _ => 1.0,
    };
    final familiar = r == null ? 0.0 : 3 + min(r.times, 5).toDouble();
    return equip + familiar;
  }

  static bool _isBodyweight(ExerciseItem i) => i.equipmentType == 'BODYWEIGHT';

  // 덤벨·케틀벨은 2kg, 나머지(바벨·머신·케이블)는 2.5kg 단위
  static double stepFor(ExerciseItem i) =>
      i.nameKo.contains('덤벨') || i.nameKo.contains('케틀벨') ? 2 : 2.5;

  // Epley 로 추정한 1RM 에서 목표 횟수에 맞는 무게를 구해 단위로 내림
  static double targetWeight(
    double weight,
    int reps,
    int targetReps,
    double step,
  ) {
    final oneRm = weight * (1 + reps / 30);
    final raw = oneRm / (1 + targetReps / 30);
    final rounded = (raw / step).floor() * step;
    return max(rounded, step);
  }

  static Recommendation _plan(
    ExerciseItem i,
    BodyPart part,
    TrainingGoal goal,
    ExerciseRecord? r,
  ) {
    if (part == BodyPart.cardio) {
      return Recommendation(
        item: i,
        part: part,
        sets: 1,
        repsMin: 0,
        repsMax: 0,
        minutes: goal.cardioMin,
        reason: '대화가 가능한 정도의 강도로 ${goal.cardioMin}분',
      );
    }

    // 복근은 목표와 상관없이 고반복
    final (sets, lo, hi) = part == BodyPart.abs
        ? (3, 12, 20)
        : (goal.sets, goal.repsMin, goal.repsMax);
    final target = (lo + hi) ~/ 2;

    if (_isBodyweight(i) || (r != null && r.topWeight <= 0)) {
      return Recommendation(
        item: i,
        part: part,
        sets: sets,
        repsMin: lo,
        repsMax: hi,
        restSec: goal.restSec,
        reason: r == null
            ? '맨몸 운동이에요. 자세가 무너지기 전까지'
            : '지난번 ${r.topReps}회 → 오늘은 ${r.topReps + 1}회 이상 도전',
      );
    }

    if (r == null) {
      return Recommendation(
        item: i,
        part: part,
        sets: sets,
        repsMin: lo,
        repsMax: hi,
        restSec: goal.restSec,
        reason:
            '처음 하는 운동이에요. 가벼운 무게로 시작해 '
            '$hi회째가 힘든 무게를 찾아보세요',
      );
    }

    final w = targetWeight(r.topWeight, r.topReps, target, stepFor(i));
    final diff = w - r.topWeight;
    final trend = diff > 0
        ? '증량'
        : diff < 0
        ? '목표 횟수에 맞춰 조정'
        : '같은 무게로 횟수 늘리기';
    return Recommendation(
      item: i,
      part: part,
      sets: sets,
      repsMin: lo,
      repsMax: hi,
      weight: w,
      restSec: goal.restSec,
      reason: '최근 ${_kg(r.topWeight)}kg × ${r.topReps}회 기준 · $trend',
    );
  }

  static String _kg(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}
