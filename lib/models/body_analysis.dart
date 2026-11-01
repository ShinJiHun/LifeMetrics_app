import 'dart:convert';

// 서버가 기록마다 저장해 둔 Claude 분석 (user_body_record.raw_llm_json)
class BodyAnalysis {
  const BodyAnalysis({
    required this.summary,
    this.muscle,
    this.fat,
    this.overall,
    this.trend,
    this.recommendations = const [],
  });

  final String summary; // 한 줄 요약
  final String? muscle; // 현재 평가: 근육
  final String? fat; // 현재 평가: 체지방
  final String? overall; // 현재 평가: 종합
  final String? trend; // 변화 추이
  final List<String> recommendations;

  bool get hasEvaluation => muscle != null || fat != null || overall != null;

  // 비어 있거나 형식이 다르면 null. LLM 이 ```json 으로 감싸 저장한 경우도 처리
  static BodyAnalysis? tryParse(String? raw) {
    if (raw == null) return null;
    final start = raw.indexOf('{'), end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;

    final Object? json;
    try {
      json = jsonDecode(raw.substring(start, end + 1));
    } on FormatException {
      return null;
    }
    if (json is! Map) return null;

    final summary = _text(json['summary']);
    if (summary == null) return null;
    final eval = json['current_evaluation'];
    final recs = json['recommendations'];

    return BodyAnalysis(
      summary: summary,
      muscle: eval is Map ? _text(eval['muscle']) : null,
      fat: eval is Map ? _text(eval['fat']) : null,
      overall: eval is Map ? _text(eval['overall']) : null,
      trend: _text(json['trend']),
      recommendations: recs is List
          ? [for (final r in recs) ?_text(r)]
          : const [],
    );
  }

  static String? _text(Object? v) =>
      v is String && v.trim().isNotEmpty ? v.trim() : null;
}
