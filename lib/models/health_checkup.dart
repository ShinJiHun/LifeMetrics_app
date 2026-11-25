// GET /api/body/health-checkups 의 건강검진 1건 (서버 HealthCheckupDto).
// 필드가 60개 가까이 되고 검진마다 비는 칸이 많아 원본 JSON 을 들고 키로 꺼내 씀
class HealthCheckup {
  HealthCheckup(this.raw)
    : id = (raw['id'] as num).toInt(),
      date = DateTime.parse(raw['checkupDate'] as String);

  factory HealthCheckup.fromJson(Map<String, dynamic> json) =>
      HealthCheckup(json);

  final Map<String, dynamic> raw;
  final int id;
  final DateTime date;

  // 숫자 칸. 비었거나 숫자가 아니면 null
  double? value(String key) => (raw[key] as num?)?.toDouble();

  // 글자 칸. 비었으면 null
  String? text(String key) {
    final v = raw[key];
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  bool? flag(String key) => raw[key] as bool?;

  String? get place => text('checkupPlace') ?? text('checkupOrg');
  String? get overall => text('overallJudgment');
  String? get suspected => text('suspectedDisease');
}

// 검진 결과의 주요 수치 하나: 이름 · 단위 · 서버 키 · 같은 영역의 판정 키
class CheckupMetric {
  const CheckupMetric(
    this.label,
    this.unit,
    this.key, {
    this.resultKey,
    this.decimals = 0,
  });

  final String label;
  final String unit;
  final String key;
  final String? resultKey; // 예: bpResult, liverResult
  final int decimals;

  String format(double v) => v.toStringAsFixed(decimals);

  // 주요 수치 화면에 보여줄 순서
  static const all = [
    CheckupMetric('수축기 혈압', 'mmHg', 'systolicBp', resultKey: 'bpResult'),
    CheckupMetric('이완기 혈압', 'mmHg', 'diastolicBp', resultKey: 'bpResult'),
    CheckupMetric(
      '공복혈당',
      'mg/dL',
      'fastingBloodSugar',
      resultKey: 'diabetesResult',
    ),
    CheckupMetric(
      '총콜레스테롤',
      'mg/dL',
      'totalCholesterol',
      resultKey: 'lipidResult',
    ),
    CheckupMetric(
      'LDL 콜레스테롤',
      'mg/dL',
      'ldlCholesterol',
      resultKey: 'lipidResult',
    ),
    CheckupMetric(
      'HDL 콜레스테롤',
      'mg/dL',
      'hdlCholesterol',
      resultKey: 'lipidResult',
    ),
    CheckupMetric('중성지방', 'mg/dL', 'triglyceride', resultKey: 'lipidResult'),
    CheckupMetric('AST', 'U/L', 'ast', resultKey: 'liverResult'),
    CheckupMetric('ALT', 'U/L', 'alt', resultKey: 'liverResult'),
    CheckupMetric('감마지티피', 'U/L', 'ggt', resultKey: 'liverResult'),
    CheckupMetric(
      '혈색소',
      'g/dL',
      'hemoglobin',
      resultKey: 'anemiaResult',
      decimals: 1,
    ),
    CheckupMetric(
      '혈청 크레아티닌',
      'mg/dL',
      'serumCreatinine',
      resultKey: 'kidneyResult',
      decimals: 2,
    ),
    CheckupMetric('eGFR', 'mL/min', 'egfr', resultKey: 'kidneyResult'),
    CheckupMetric('체중', 'kg', 'weightKg', decimals: 1),
    CheckupMetric('BMI', '', 'bmi', resultKey: 'bmiGrade', decimals: 1),
    CheckupMetric(
      '허리둘레',
      'cm',
      'waistCm',
      resultKey: 'waistResult',
      decimals: 1,
    ),
  ];
}
