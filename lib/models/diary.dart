// 인간 일기 (서버 /api/diary). 하루 메모를 모아 밤 10시에 일기 초안을 만들고, 확인 후 블로그에 게시

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;

// 하루 동안 모은 메모 하나. source: app(Claude 앱) · cli(Claude Code) · manual(직접)
class DiaryNote {
  const DiaryNote({
    required this.id,
    required this.source,
    required this.content,
    this.fileName,
    this.createdAt,
  });

  final int id;
  final String source;
  final String content;
  final String? fileName;
  final DateTime? createdAt;

  String get sourceLabel => switch (source) {
    'app' => 'Claude 앱',
    'cli' => 'Claude Code',
    _ => '직접',
  };

  factory DiaryNote.fromJson(Map<String, Object?> j) => DiaryNote(
    id: (j['id'] as num).toInt(),
    source: (j['source'] as String?) ?? 'manual',
    content: (j['content'] as String?) ?? '',
    fileName: j['fileName'] as String?,
    createdAt: _time(j['createdAt']),
  );
}

// 메모로 만든 글 (일기 또는 독서 기록). status: draft | published
class DiaryEntry {
  const DiaryEntry({
    required this.id,
    required this.kind,
    required this.title,
    required this.content,
    this.warnings = const [],
    this.status = 'draft',
    this.edited = false,
    this.postId,
    this.generatedAt,
    this.publishedAt,
  });

  final int id;
  final String kind; // diary | book
  final String title;
  final String content;
  final List<String> warnings; // 실명 · 회사 · 건강 같은 게시 전 확인할 것
  final String status;
  final bool edited; // 사람이 고침 → 밤 10시 배치가 덮어쓰지 않음
  final int? postId;
  final DateTime? generatedAt;
  final DateTime? publishedAt;

  bool get isPublished => status == 'published';
  bool get isBook => kind == 'book';

  factory DiaryEntry.fromJson(Map<String, Object?> j) => DiaryEntry(
    id: (j['id'] as num).toInt(),
    kind: (j['kind'] as String?) ?? 'diary',
    title: (j['title'] as String?) ?? '',
    content: (j['content'] as String?) ?? '',
    warnings: [for (final w in (j['warnings'] as List?) ?? const []) '$w'],
    status: (j['status'] as String?) ?? 'draft',
    edited: j['edited'] == true,
    postId: (j['postId'] as num?)?.toInt(),
    generatedAt: _time(j['generatedAt']),
    publishedAt: _time(j['publishedAt']),
  );
}

class DiaryDay {
  const DiaryDay({
    required this.date,
    this.notes = const [],
    this.diary,
    this.book,
    this.recordKinds = const [],
  });

  final DateTime date;
  final List<DiaryNote> notes;
  final DiaryEntry? diary;
  final DiaryEntry? book;
  final List<String> recordKinds; // 초안에 함께 들어가는 그날 기록 (웨이트 · 라이딩 ...)

  static const _recordLabels = {
    'fitness': '웨이트',
    'rides': '라이딩',
    'bodyRecords': '체성분',
    'phoneExercises': '폰 운동',
    'dailyActivity': '걸음 · 활동',
  };

  factory DiaryDay.fromJson(Map<String, Object?> j) {
    Map<String, Object?>? map(Object? v) =>
        v is Map ? v.cast<String, Object?>() : null;
    final records = map(j['records']) ?? const {};
    return DiaryDay(
      date: DateTime.parse(j['date'] as String),
      notes: [
        for (final n in (j['notes'] as List?) ?? const [])
          DiaryNote.fromJson((n as Map).cast<String, Object?>()),
      ],
      diary: map(j['diary']) == null
          ? null
          : DiaryEntry.fromJson(map(j['diary'])!),
      book: map(j['book']) == null ? null : DiaryEntry.fromJson(map(j['book'])!),
      recordKinds: [
        for (final k in records.keys) _recordLabels[k] ?? k,
      ],
    );
  }
}

// 게시할 수 있는 인간 블로그 소메뉴 (예: 일기 › 26년)
class DiarySubMenu {
  const DiarySubMenu({
    required this.id,
    required this.category,
    required this.name,
  });

  final int id;
  final String category;
  final String name;

  String get label => '$category › $name';

  factory DiarySubMenu.fromJson(Map<String, Object?> j) => DiarySubMenu(
    id: (j['id'] as num).toInt(),
    category: (j['category'] as String?) ?? '',
    name: (j['name'] as String?) ?? '',
  );
}

class DiarySubMenus {
  const DiarySubMenus({required this.subs, required this.diaryDefault});

  final List<DiarySubMenu> subs;
  final int diaryDefault; // 일기를 올릴 기본 소메뉴

  factory DiarySubMenus.fromJson(Map<String, Object?> j) => DiarySubMenus(
    subs: [
      for (final s in (j['subs'] as List?) ?? const [])
        DiarySubMenu.fromJson((s as Map).cast<String, Object?>()),
    ],
    diaryDefault: (j['diaryDefault'] as num).toInt(),
  );
}
