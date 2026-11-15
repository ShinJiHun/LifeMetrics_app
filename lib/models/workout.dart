// GET /api/exercise/categories 의 부위 1개
class ExerciseCategory {
  const ExerciseCategory({required this.id, required this.name});

  factory ExerciseCategory.fromJson(Map<String, dynamic> json) =>
      ExerciseCategory(id: json['id'] as int, name: json['name'] as String);

  final int id;
  final String name;
}

// GET /api/exercise/items 의 운동 종목 1개
class ExerciseItem {
  const ExerciseItem({
    required this.id,
    required this.categoryId,
    required this.nameKo,
    this.nameEn,
    this.equipmentType,
    this.description,
    this.gifUrl,
  });

  factory ExerciseItem.fromJson(Map<String, dynamic> json) => ExerciseItem(
    id: json['id'] as int,
    categoryId: json['categoryId'] as int,
    nameKo: json['nameKo'] as String,
    nameEn: json['nameEn'] as String?,
    equipmentType: json['equipmentType'] as String?,
    description: json['description'] as String?,
    gifUrl: json['gifUrl'] as String?,
  );

  final int id;
  final int categoryId;
  final String nameKo;
  final String? nameEn;
  final String? equipmentType; // FREE_WEIGHT, MACHINE ...
  final String? description; // 동작 설명
  final String? gifUrl; // 서버 경로 (/api/exercise/gif/chest/PUSH_UP.gif), 없으면 null

  bool get hasGif => gifUrl != null && gifUrl!.isNotEmpty;

  // 오늘 계획을 폰에 저장할 때 (fromJson 과 같은 키)
  Map<String, dynamic> toJson() => {
    'id': id,
    'categoryId': categoryId,
    'nameKo': nameKo,
    'nameEn': nameEn,
    'equipmentType': equipmentType,
    'description': description,
    'gifUrl': gifUrl,
  };

  // 웹 대시보드와 같은 한글 이름
  String? get equipmentLabel => switch (equipmentType) {
    'FREE_WEIGHT' => '프리웨이트',
    'MACHINE' => '머신',
    'CABLE' => '케이블',
    'BODYWEIGHT' => '맨몸',
    'BAND' => '밴드',
    'MIXED' => '복합',
    _ => equipmentType,
  };

  // 한글/영문 이름에 검색어가 들어 있는지
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty ||
        nameKo.toLowerCase().contains(q) ||
        (nameEn?.toLowerCase().contains(q) ?? false);
  }
}

class WorkoutSet {
  const WorkoutSet({required this.setNumber, this.weight, this.reps});

  factory WorkoutSet.fromJson(Map<String, dynamic> json) => WorkoutSet(
    setNumber: json['setNumber'] as int,
    weight: (json['weight'] as num?)?.toDouble(),
    reps: json['reps'] as int?,
  );

  final int setNumber;
  final double? weight; // kg
  final int? reps;

  Map<String, dynamic> toJson() => {
    'setNumber': setNumber,
    'weight': weight,
    'reps': reps,
  };
}

// 세션 안의 운동 1개와 세트들
class WorkoutExercise {
  const WorkoutExercise({
    required this.exerciseItemId,
    required this.sets,
    this.nameKo,
    this.categoryName,
    this.memo,
  });

  factory WorkoutExercise.fromJson(Map<String, dynamic> json) =>
      WorkoutExercise(
        exerciseItemId: json['exerciseItemId'] as int,
        nameKo: json['exerciseNameKo'] as String?,
        categoryName: json['categoryName'] as String?,
        memo: json['memo'] as String?,
        sets:
            (json['sets'] as List? ?? const [])
                .map((e) => WorkoutSet.fromJson(e as Map<String, dynamic>))
                .toList()
              ..sort((a, b) => a.setNumber.compareTo(b.setNumber)),
      );

  final int exerciseItemId;
  final String? nameKo;
  final String? categoryName;
  final String? memo;
  final List<WorkoutSet> sets;

  // POST /api/exercise/log 의 exercises 항목
  Map<String, dynamic> toLogJson() => {
    'exerciseItemId': exerciseItemId,
    'restTimeSec': 60,
    'memo': memo,
    'sets': [for (final s in sets) s.toJson()],
  };
}

// 유산소 1건. 서버는 durationMin 이 있으면 세트 대신 시간 · 거리 · 칼로리 · 심박으로 저장
class CardioLog {
  const CardioLog({
    required this.exerciseItemId,
    required this.minutes,
    required this.name,
    this.distanceKm,
    this.kcal,
    this.avgHr,
    this.memo,
  });

  final int exerciseItemId;
  final String name; // 화면 표시용
  final double minutes;
  final double? distanceKm;
  final int? kcal; // 기기에 나온 값
  final int? avgHr;
  final String? memo; // 경사 · 속도 · 레벨 같은 기기 설정

  Map<String, dynamic> toLogJson() => {
    'exerciseItemId': exerciseItemId,
    'durationMin': minutes,
    'distanceKm': distanceKm,
    'kcal': kcal,
    'avgHr': avgHr,
    'memo': memo,
    'sets': const [],
  };
}

// GET /api/exercise/history 의 하루 운동 1건
class WorkoutSession {
  const WorkoutSession({
    required this.id,
    required this.date,
    required this.isPT,
    required this.exercises,
    this.memo,
    this.totalVolume,
    this.totalSets,
    this.estimatedMinutes,
    this.estimatedCalories,
  });

  factory WorkoutSession.fromJson(Map<String, dynamic> json) => WorkoutSession(
    id: json['id'] as int,
    date: DateTime.parse(json['sessionDate'] as String),
    isPT: json['isPT'] as bool? ?? false,
    memo: json['memo'] as String?,
    exercises: (json['logs'] as List? ?? const [])
        .map((e) => WorkoutExercise.fromJson(e as Map<String, dynamic>))
        .toList(),
    totalVolume: (json['totalVolume'] as num?)?.toDouble(),
    totalSets: json['totalSets'] as int?,
    estimatedMinutes: json['estimatedMinutes'] as int?,
    estimatedCalories: (json['estimatedCalories'] as num?)?.toDouble(),
  );

  final int id;
  final DateTime date;
  final bool isPT;
  final String? memo;
  final List<WorkoutExercise> exercises;
  final double? totalVolume; // kg × 횟수 합
  final int? totalSets;
  final int? estimatedMinutes;
  final double? estimatedCalories;

  // 이날 운동한 부위, 나온 순서대로 중복 없이
  List<String> get categories => {
    for (final e in exercises)
      if (e.categoryName != null) e.categoryName!,
  }.toList();
}

// GET /api/ai/analysis/exercise/{sessionId}
class WorkoutAnalysis {
  const WorkoutAnalysis({
    required this.summary,
    this.score,
    this.volumeLevel,
    this.intensityLevel,
    this.highlights = const [],
    this.suggestions = const [],
  });

  factory WorkoutAnalysis.fromJson(Map<String, dynamic> json) =>
      WorkoutAnalysis(
        summary: json['summary'] as String? ?? '',
        score: (json['score'] as num?)?.round(),
        volumeLevel: json['volumeLevel'] as String?,
        intensityLevel: json['intensityLevel'] as String?,
        highlights: [...?(json['highlights'] as List?)?.cast<String>()],
        suggestions: [...?(json['suggestions'] as List?)?.cast<String>()],
      );

  final String summary;
  final int? score; // 0~100
  final String? volumeLevel; // 낮음 / 보통 / 높음
  final String? intensityLevel;
  final List<String> highlights; // 잘한 점
  final List<String> suggestions; // 다음에 해볼 것

  // 서버가 분석에 실패하면 이 문구를 summary 에 넣어 줌 (웹도 숨김)
  bool get isValid =>
      summary.isNotEmpty && summary != '분석 실패' && summary != 'API 키 없음';
}
