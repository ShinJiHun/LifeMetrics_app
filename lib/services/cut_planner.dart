import 'dart:math';

// 감량 목표 → 오늘 칼로리 수지 → 헬스장 유산소 시간 · 강도.
// 숫자는 모두 추정치라 화면에서도 '약' 으로 보여줌

const kcalPerKgFat = 7700.0;

// 오늘 하루의 입력값. 모르는 값은 null
class EnergyInputs {
  const EnergyInputs({
    required this.weightKg,
    required this.bmr,
    required this.monthlyLossKg,
    this.intakeKcal,
    this.mealCount = 0,
    this.steps,
    this.activeKcal,
    this.bikeKcal = 0,
    this.bikeMinutes = 0,
    this.bikeRides = 0,
    this.strengthMinutes = 0,
    this.ftp,
    this.hour = 12,
  });

  final double weightKg;
  final double bmr; // 기초대사량
  final double monthlyLossKg; // 한 달 감량 목표
  final double? intakeKcal; // 오늘 지금까지 먹은 것 (삼성헬스 식사 기록)
  final int mealCount;
  final int? steps;
  final double? activeKcal; // 삼성헬스 활동 칼로리 (걸음 포함)
  final double bikeKcal; // 오늘 따릉이
  final int bikeMinutes;
  final int bikeRides;
  final int strengthMinutes; // 오늘 할 웨이트 (추천 받은 운동 기준)
  final int? ftp;
  final int hour; // 지금 시각(시). 저녁인데 섭취가 너무 적으면 알려줌
}

// 헬스장 유산소 기구. 서버 종목은 이름으로 찾고, 기구마다 따로 적을 설정이 다름
enum CardioMachine {
  treadmill(
    ['러닝머신', '트레드밀'],
    [('incline', '경사', '%'), ('speed', '속도', 'km/h')],
  ),
  cycle(
    ['실내 사이클', '사이클', '싸이클', '바이크'],
    [('watts', '평균 파워', 'W'), ('cadence', '케이던스', 'rpm')],
  ),
  stepmill(['천국의 계단', '스텝밀'], [('level', '레벨', '')]),
  rowing(['로잉'], [('level', '저항', ''), ('pace', '500m 페이스', '')]);

  const CardioMachine(this.names, this.extras);

  final List<String> names; // 서버 종목 이름에 들어가는 말
  final List<(String, String, String)> extras; // (키, 이름, 단위)

  static CardioMachine? byName(String? name) {
    for (final m in values) {
      if (m.name == name) return m;
    }
    return null;
  }
}

// 유산소 한 가지 처방
class CardioOption {
  const CardioOption({
    required this.machine,
    required this.name,
    required this.gifUrl,
    required this.minutes,
    required this.kcal,
    required this.intensity,
    required this.how,
    this.primary = false,
  });

  final CardioMachine machine;
  final String name;
  final String gifUrl;
  final int minutes;
  final double kcal;
  final String intensity; // 'Zone 2', '중강도', '인터벌'
  final String how; // 기계 설정
  final bool primary; // 오늘 가장 추천
}

class CutPlan {
  const CutPlan({
    required this.targetDeficit,
    required this.bmr,
    required this.tef,
    required this.activeKcal,
    required this.activeFromSteps,
    required this.bikeKcal,
    required this.strengthKcal,
    required this.intake,
    required this.remaining,
    required this.options,
    required this.notes,
    this.foodCut = 0,
  });

  final double targetDeficit; // 하루에 만들어야 할 적자
  final double bmr;
  final double tef; // 먹은 것 소화에 드는 열량 (섭취의 10%)
  final double activeKcal;
  final bool activeFromSteps; // 활동 칼로리가 없어 걸음으로 추정
  final double bikeKcal;
  final double strengthKcal;
  final double? intake; // null 이면 식사 기록 없음
  final double remaining; // 유산소로 더 태워야 할 kcal (0 이하면 이미 달성)
  final List<CardioOption> options;
  final List<String> notes;
  final double foodCut; // 유산소 상한(60분)을 넘는 부분, 식사로 줄일 kcal

  double get burned => bmr + tef + activeKcal + bikeKcal + strengthKcal;
  double? get balance => intake == null ? null : intake! - burned; // 음수면 적자
}

class CutPlanner {
  // 체중의 주 1% 를 넘는 감량은 근손실 위험이 커서 상한으로 둠
  static double maxMonthlyLoss(double weightKg) =>
      (weightKg * 0.01 * 30 / 7 * 2).floor() / 2;

  // 인바디 목표까지 남은 감량을 남은 달 수로 나눈 값, 0.5kg 단위.
  // 목표가 없거나 지났으면 체중의 2%/월 (한 달 0.5%/주 정도)
  static double suggestMonthlyLoss({
    required double weightKg,
    double? targetWeight,
    DateTime? targetDate,
    required DateTime today,
  }) {
    double raw = weightKg * 0.02;
    if (targetWeight != null &&
        targetDate != null &&
        targetWeight < weightKg &&
        targetDate.isAfter(today)) {
      final months = targetDate.difference(today).inDays / 30.4;
      raw = (weightKg - targetWeight) / max(months, 1);
    }
    final rounded = (raw * 2).round() / 2;
    return rounded.clamp(0.5, maxMonthlyLoss(weightKg));
  }

  // 활동 대사(MET) → 분당 kcal. ACSM 식: MET × 3.5 × kg ÷ 200
  static double kcalPerMin(double met, double kg) => met * 3.5 * kg / 200;

  static CutPlan plan(EnergyInputs x) {
    final notes = <String>[];
    final kg = x.weightKg;
    final targetDeficit = x.monthlyLossKg * kcalPerKgFat / 30;

    // 삼성헬스 활동 칼로리가 없으면 걸음으로 추정 (70kg 기준 1보 0.04kcal)
    final fromSteps = x.activeKcal == null && x.steps != null;
    final active =
        x.activeKcal ?? (x.steps == null ? 0.0 : x.steps! * 0.04 * kg / 70);
    final strength = kcalPerMin(5.0, kg) * x.strengthMinutes;
    final intake = x.mealCount == 0 ? null : x.intakeKcal;
    final tef = (intake ?? 0) * 0.1;
    final burned = x.bmr + tef + active + x.bikeKcal + strength;

    // 식사 기록이 없으면 섭취를 알 수 없어, 목표 적자의 절반을 유산소로 잡고 나머지는 식사로
    final double remaining;
    if (intake == null) {
      remaining = targetDeficit / 2;
      notes.add(
        '오늘 식사 기록이 없어 목표 적자의 절반을 유산소로 잡았어요. '
        '오늘 섭취는 약 ${(burned + remaining - targetDeficit).round()}kcal 이하로',
      );
    } else {
      remaining = targetDeficit - (burned - intake);
    }

    if (x.steps != null && x.steps! < 5000) {
      notes.add('걸음이 ${x.steps}보로 적어요. 트레드밀 걷기로 걸음도 채워 보세요');
    }
    if (x.bikeRides > 0 && x.activeKcal != null) {
      notes.add('워치를 차고 따릉이를 탔다면 활동 칼로리에 이미 들어가 있어 조금 겹칠 수 있어요');
    }
    if (intake != null && intake < x.bmr * 0.8 && x.hour >= 18) {
      notes.add('섭취가 기초대사량보다 많이 적어요. 단백질은 체중 1kg 당 1.6g 이상 챙겨 주세요');
    }

    if (remaining <= 0) {
      return CutPlan(
        targetDeficit: targetDeficit,
        bmr: x.bmr,
        tef: tef,
        activeKcal: active,
        activeFromSteps: fromSteps,
        bikeKcal: x.bikeKcal,
        strengthKcal: strength,
        intake: intake,
        remaining: remaining,
        options: [_recovery(kg)],
        notes: ['오늘은 목표 적자를 이미 채웠어요. 유산소는 회복용으로 가볍게', ...notes],
      );
    }

    // 60분을 넘기면 근손실 · 피로가 커서 상한. 넘는 부분은 식사로
    const capMin = 60;
    int minutesFor(double met) {
      final m = (remaining / kcalPerMin(met, kg) / 5).ceil() * 5;
      return m.clamp(15, capMin);
    }

    final ftp = x.ftp;
    final options = <CardioOption>[
      _option(
        CardioMachine.treadmill,
        '트레드밀 경사 걷기',
        'cardio/TREADMILL.gif',
        6.0,
        kg,
        minutesFor(6.0),
        'Zone 2',
        '경사 10~12% · 속도 5~5.5km/h · 손잡이 잡지 않기',
      ),
      _option(
        CardioMachine.cycle,
        '실내 사이클',
        'cardio/CYCLING.gif',
        6.8,
        kg,
        minutesFor(6.8),
        'Zone 2',
        ftp == null
            ? '대화가 가능한 강도 (힘듦 10 중 4~5) · 케이던스 85~95'
            : '${(ftp * 0.56).round()}~${(ftp * 0.75).round()}W '
                  '(FTP $ftp 의 56~75%) · 케이던스 85~95',
      ),
      _option(
        CardioMachine.stepmill,
        '스텝밀',
        'cardio/STEPMILL.gif',
        9.0,
        kg,
        minutesFor(9.0),
        '중강도',
        '레벨 6~8 · 상체 세우고 손잡이 가볍게',
      ),
    ];

    // 남은 양이 많으면 짧고 강한 인터벌도 보기로 (최대 25분)
    if (remaining > 400) {
      final m = (remaining / kcalPerMin(9.5, kg) / 5).ceil() * 5;
      options.add(
        _option(
          CardioMachine.rowing,
          '로잉 인터벌',
          'cardio/ROWING_MACHINE.gif',
          9.5,
          kg,
          m.clamp(15, 25),
          '인터벌',
          '30초 강하게 / 90초 천천히 반복 · 워밍업 5분 포함',
        ),
      );
    }

    // 걸음이 이미 많거나 하체를 했으면 무릎 부담이 적은 사이클, 아니면 걷기로 걸음도 채움
    final primaryName = (x.steps ?? 0) >= 10000 || x.bikeMinutes >= 40
        ? '실내 사이클'
        : remaining > 450
        ? '스텝밀'
        : '트레드밀 경사 걷기';
    final marked = [
      for (final o in options) o.name == primaryName ? _withPrimary(o) : o,
    ];
    final best = marked.firstWhere((o) => o.primary);
    final foodCut = max(0.0, remaining - best.kcal);
    if (foodCut >= 50) {
      notes.insert(
        0,
        '유산소는 60분까지만 권해요. 나머지 약 ${foodCut.round()}kcal 는 '
        '오늘 남은 식사에서 줄여 주세요',
      );
    }

    return CutPlan(
      targetDeficit: targetDeficit,
      bmr: x.bmr,
      tef: tef,
      activeKcal: active,
      activeFromSteps: fromSteps,
      bikeKcal: x.bikeKcal,
      strengthKcal: strength,
      intake: intake,
      remaining: remaining,
      options: marked,
      notes: notes,
      foodCut: foodCut,
    );
  }

  static CardioOption _option(
    CardioMachine machine,
    String name,
    String gif,
    double met,
    double kg,
    int minutes,
    String intensity,
    String how,
  ) => CardioOption(
    machine: machine,
    name: name,
    gifUrl: '/api/exercise/gif/$gif',
    minutes: minutes,
    kcal: kcalPerMin(met, kg) * minutes,
    intensity: intensity,
    how: how,
  );

  static CardioOption _withPrimary(CardioOption o) => CardioOption(
    machine: o.machine,
    name: o.name,
    gifUrl: o.gifUrl,
    minutes: o.minutes,
    kcal: o.kcal,
    intensity: o.intensity,
    how: o.how,
    primary: true,
  );

  static CardioOption _recovery(double kg) => _withPrimary(
    _option(
      CardioMachine.treadmill,
      '트레드밀 걷기',
      'cardio/TREADMILL.gif',
      3.5,
      kg,
      20,
      '회복',
      '경사 3~5% · 속도 5km/h · 편하게',
    ),
  );
}
