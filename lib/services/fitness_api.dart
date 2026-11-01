import 'package:http/http.dart' as http;

import '../models/workout.dart';
import 'api_client.dart';

// 백엔드 /api/exercise
class FitnessApi {
  FitnessApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  // 운동 부위 (가슴, 등 ...)
  Future<List<ExerciseCategory>> fetchCategories() async {
    final list = await getJson(_client, '/api/exercise/categories') as List;
    return list
        .map((e) => ExerciseCategory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // 전체 운동 종목, 이름순
  Future<List<ExerciseItem>> fetchItems() async {
    final list = await getJson(_client, '/api/exercise/items') as List;
    return list
        .map((e) => ExerciseItem.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.nameKo.compareTo(b.nameKo));
  }

  // 한 달 운동 기록, 최신 날짜부터
  Future<List<WorkoutSession>> fetchHistory(DateTime month) async {
    final key = '${month.year}-${month.month.toString().padLeft(2, '0')}';
    final list = await getJson(
      _client,
      '/api/exercise/history',
      query: {'month': key},
    ) as List;
    return list
        .map((e) => WorkoutSession.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  // 세션 AI 분석. 분석이 없으면 서버가 빈 본문(200)을 주므로 null
  Future<WorkoutAnalysis?> fetchAnalysis(int sessionId) async {
    final Object? body;
    try {
      body = await getJson(_client, '/api/ai/analysis/exercise/$sessionId');
    } on ApiException {
      return null;
    } on FormatException {
      return null;
    }
    if (body is! Map<String, dynamic>) return null;
    final analysis = WorkoutAnalysis.fromJson(body);
    return analysis.isValid ? analysis : null;
  }

  // 관리자 로그인. 기록 저장은 관리자만 할 수 있음
  Future<bool> loginAdmin(String password) => postAdminLogin(_client, password);

  // 하루 운동 저장
  Future<void> logWorkout({
    required DateTime date,
    required bool isPT,
    required List<WorkoutExercise> exercises,
  }) => postJson(_client, '/api/exercise/log', {
    'sessionDate':
        '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}',
    'userId': apiUserId,
    'isPT': isPT,
    'exercises': [for (final e in exercises) e.toLogJson()],
  });
}
