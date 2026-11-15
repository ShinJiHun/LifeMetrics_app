import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/cut_planner.dart';
import '../services/workout_recommender.dart';
import 'workout.dart';

// '오늘 추천 저장' 으로 확정한 하루 계획. 폰에만 저장하고, 입력하면 서버 기록이 됨
class TodayPlan {
  const TodayPlan({
    required this.date,
    required this.goal,
    required this.exercises,
    this.cardio,
    this.logged = false,
  });

  factory TodayPlan.fromJson(Map<String, dynamic> j) => TodayPlan(
    date: DateTime.parse(j['date'] as String),
    goal: TrainingGoal.values.byName(j['goal'] as String),
    exercises: [
      for (final e in j['exercises'] as List)
        _recFromJson(e as Map<String, dynamic>),
    ],
    cardio: j['cardio'] == null
        ? null
        : PlannedCardio.fromJson(j['cardio'] as Map<String, dynamic>),
    logged: j['logged'] as bool? ?? false,
  );

  final DateTime date; // 그날 00:00
  final TrainingGoal goal;
  final List<Recommendation> exercises; // 웨이트 (유산소 제외)
  final PlannedCardio? cardio; // 감량에서 고른 유산소 1개
  final bool logged; // 서버에 기록까지 했는지

  bool isFor(DateTime now) =>
      date.year == now.year && date.month == now.month && date.day == now.day;

  TodayPlan copyWith({PlannedCardio? cardio, bool? logged}) => TodayPlan(
    date: date,
    goal: goal,
    exercises: exercises,
    cardio: cardio ?? this.cardio,
    logged: logged ?? this.logged,
  );

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'goal': goal.name,
    'exercises': [for (final r in exercises) _recToJson(r)],
    'cardio': cardio?.toJson(),
    'logged': logged,
  };

  static Map<String, dynamic> _recToJson(Recommendation r) => {
    'item': r.item.toJson(),
    'part': r.part.name,
    'sets': r.sets,
    'repsMin': r.repsMin,
    'repsMax': r.repsMax,
    'weight': r.weight,
    'minutes': r.minutes,
    'restSec': r.restSec,
    'reason': r.reason,
  };

  static Recommendation _recFromJson(Map<String, dynamic> j) => Recommendation(
    item: ExerciseItem.fromJson(j['item'] as Map<String, dynamic>),
    part: BodyPart.values.byName(j['part'] as String),
    sets: j['sets'] as int,
    repsMin: j['repsMin'] as int,
    repsMax: j['repsMax'] as int,
    weight: (j['weight'] as num?)?.toDouble(),
    minutes: j['minutes'] as int?,
    restSec: j['restSec'] as int?,
    reason: j['reason'] as String,
  );
}

// 고른 유산소와, 하고 나서 적는 실제 값(입력 중인 값도 그대로 보관)
class PlannedCardio {
  const PlannedCardio({
    required this.machine,
    required this.name,
    required this.gifUrl,
    required this.targetMinutes,
    required this.targetKcal,
    required this.intensity,
    required this.how,
    this.itemId,
    this.actual = const {},
  });

  factory PlannedCardio.fromOption(CardioOption o, {int? itemId}) =>
      PlannedCardio(
        machine: o.machine,
        name: o.name,
        gifUrl: o.gifUrl,
        targetMinutes: o.minutes,
        targetKcal: o.kcal.round(),
        intensity: o.intensity,
        how: o.how,
        itemId: itemId,
      );

  factory PlannedCardio.fromJson(Map<String, dynamic> j) => PlannedCardio(
    machine:
        CardioMachine.byName(j['machine'] as String?) ??
        CardioMachine.treadmill,
    name: j['name'] as String,
    gifUrl: j['gifUrl'] as String,
    targetMinutes: j['targetMinutes'] as int,
    targetKcal: j['targetKcal'] as int,
    intensity: j['intensity'] as String,
    how: j['how'] as String,
    itemId: j['itemId'] as int?,
    actual: {
      for (final MapEntry(:key, :value)
          in (j['actual'] as Map? ?? const {}).entries)
        key as String: value as String,
    },
  );

  final CardioMachine machine;
  final String name;
  final String gifUrl;
  final int targetMinutes;
  final int targetKcal;
  final String intensity;
  final String how;
  final int? itemId; // 서버 종목 id. 서버에 그 기구 종목이 없으면 null (기록 불가)

  // 입력칸 값 그대로: minutes, kcal, distance, avgHr + 기구별(incline, speed, watts ...)
  final Map<String, String> actual;

  PlannedCardio withActual(Map<String, String> v) => PlannedCardio(
    machine: machine,
    name: name,
    gifUrl: gifUrl,
    targetMinutes: targetMinutes,
    targetKcal: targetKcal,
    intensity: intensity,
    how: how,
    itemId: itemId,
    actual: v,
  );

  double? get actualMinutes => double.tryParse(actual['minutes'] ?? '');

  // 기구 설정은 서버에 칸이 없어 메모로: '경사 12% · 속도 5.5km/h'
  String? get settingsMemo {
    final parts = [
      for (final (key, label, unit) in machine.extras)
        if ((actual[key] ?? '').trim().isNotEmpty)
          '$label ${actual[key]!.trim()}$unit',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  // 시간을 적었고 서버 종목이 있으면 기록으로
  CardioLog? toLog() {
    final m = actualMinutes;
    if (m == null || m <= 0 || itemId == null) return null;
    return CardioLog(
      exerciseItemId: itemId!,
      name: name,
      minutes: m,
      distanceKm: double.tryParse(actual['distance'] ?? ''),
      kcal: int.tryParse(actual['kcal'] ?? ''),
      avgHr: int.tryParse(actual['avgHr'] ?? ''),
      memo: settingsMemo,
    );
  }

  Map<String, dynamic> toJson() => {
    'machine': machine.name,
    'name': name,
    'gifUrl': gifUrl,
    'targetMinutes': targetMinutes,
    'targetKcal': targetKcal,
    'intensity': intensity,
    'how': how,
    'itemId': itemId,
    'actual': actual,
  };
}

// 하루 계획 1개만 보관. 날짜가 지나면 load 가 null
class TodayPlanStore {
  static const _key = 'today_plan';

  static Future<TodayPlan?> load(DateTime now) async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return null;
      final plan = TodayPlan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      return plan.isFor(now) ? plan : null;
    } catch (_) {
      return null; // 저장 형식이 바뀌었거나 플러그인이 없는 환경
    }
  }

  static Future<void> save(TodayPlan plan) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(plan.toJson()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
