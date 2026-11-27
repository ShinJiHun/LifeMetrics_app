// 증권 페르소나 — 토스증권 계좌 (서버 /api/stock, 관리자 전용 · 읽기만).
// 숫자는 서버 BigDecimal → JSON number. 수익률(pnlRate 등)은 0.0123 = 1.23% 같은 비율

double? _d(Object? v) => (v as num?)?.toDouble();
double _d0(Object? v) => (v as num?)?.toDouble() ?? 0;
DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;

List<Map<String, Object?>> _maps(Object? v) =>
    v is List ? v.whereType<Map<String, Object?>>().toList() : const [];

// 장 마감 때마다 찍는 계좌 스냅샷. session: KR_CLOSE(국내 마감) · US_CLOSE(미국 마감)
class AccountSnapshot {
  const AccountSnapshot({
    required this.snapshotAt,
    required this.session,
    this.accountSuffix = '',
    this.purchaseKrw,
    this.purchaseUsd,
    this.evalKrw,
    this.evalUsd,
    this.pnlKrw,
    this.pnlUsd,
    this.pnlRate,
    this.pnlRateAfterCost,
    this.dailyPnlKrw,
    this.dailyPnlUsd,
    this.dailyPnlRate,
    this.holdingCount = 0,
  });

  final DateTime snapshotAt;
  final String session;
  final String accountSuffix;
  final double? purchaseKrw, purchaseUsd;
  final double? evalKrw, evalUsd;
  final double? pnlKrw, pnlUsd;
  final double? pnlRate, pnlRateAfterCost;
  final double? dailyPnlKrw, dailyPnlUsd, dailyPnlRate;
  final int holdingCount;

  String get sessionLabel => switch (session) {
    'KR_CLOSE' => '국내 마감',
    'US_CLOSE' => '미국 마감',
    _ => session,
  };

  factory AccountSnapshot.fromJson(Map<String, Object?> j) => AccountSnapshot(
    snapshotAt: _time(j['snapshotAt']) ?? DateTime(1970),
    session: (j['session'] as String?) ?? '',
    accountSuffix: (j['accountSuffix'] as String?) ?? '',
    purchaseKrw: _d(j['purchaseKrw']),
    purchaseUsd: _d(j['purchaseUsd']),
    evalKrw: _d(j['evalKrw']),
    evalUsd: _d(j['evalUsd']),
    pnlKrw: _d(j['pnlKrw']),
    pnlUsd: _d(j['pnlUsd']),
    pnlRate: _d(j['pnlRate']),
    pnlRateAfterCost: _d(j['pnlRateAfterCost']),
    dailyPnlKrw: _d(j['dailyPnlKrw']),
    dailyPnlUsd: _d(j['dailyPnlUsd']),
    dailyPnlRate: _d(j['dailyPnlRate']),
    holdingCount: (j['holdingCount'] as num?)?.toInt() ?? 0,
  );
}

// 보유 종목 하나. currency: KRW · USD (금액은 그 통화 기준)
class Holding {
  const Holding({
    required this.market,
    required this.symbol,
    required this.currency,
    required this.quantity,
    this.name,
    this.avgPrice,
    this.currentPrice,
    this.purchaseAmount,
    this.evalAmount,
    this.pnl,
    this.pnlRate,
    this.dailyPnl,
    this.dailyPnlRate,
  });

  final String market;
  final String symbol;
  final String? name;
  final String currency;
  final double quantity;
  final double? avgPrice, currentPrice;
  final double? purchaseAmount, evalAmount;
  final double? pnl, pnlRate;
  final double? dailyPnl, dailyPnlRate;

  String get displayName => (name == null || name!.isEmpty) ? symbol : name!;

  factory Holding.fromJson(Map<String, Object?> j) => Holding(
    market: (j['market'] as String?) ?? '',
    symbol: (j['symbol'] as String?) ?? '',
    name: j['name'] as String?,
    currency: (j['currency'] as String?) ?? 'KRW',
    quantity: _d0(j['quantity']),
    avgPrice: _d(j['avgPrice']),
    currentPrice: _d(j['currentPrice']),
    purchaseAmount: _d(j['purchaseAmount']),
    evalAmount: _d(j['evalAmount']),
    pnl: _d(j['pnl']),
    pnlRate: _d(j['pnlRate']),
    dailyPnl: _d(j['dailyPnl']),
    dailyPnlRate: _d(j['dailyPnlRate']),
  );
}

// /api/stock/summary — 최신 스냅샷 · 보유 종목 · 최근 스냅샷(최신순, 최대 120개)
class StockSummary {
  const StockSummary({
    this.latest,
    this.holdings = const [],
    this.history = const [],
  });

  final AccountSnapshot? latest;
  final List<Holding> holdings;
  final List<AccountSnapshot> history;

  factory StockSummary.fromJson(Map<String, Object?> j) => StockSummary(
    latest: j['latest'] is Map<String, Object?>
        ? AccountSnapshot.fromJson(j['latest'] as Map<String, Object?>)
        : null,
    holdings: _maps(j['holdings']).map(Holding.fromJson).toList(),
    history: _maps(j['history']).map(AccountSnapshot.fromJson).toList(),
  );
}

// /api/stock/profit — 총 수익 = (보유 평가 + 추정 현금) − (입금 − 출금). 원화 값은 원 단위
class StockProfit {
  const StockProfit({
    this.firstDate,
    this.lastDate,
    this.txCount = 0,
    this.holdingsKrw,
    this.holdingsUsd,
    this.usdKrw,
    this.usdKrwDate,
    this.depositKrw = 0,
    this.withdrawalKrw = 0,
    this.netDepositKrw = 0,
    this.cashKrw = 0,
    this.holdingsTotalKrw = 0,
    this.currentAssetKrw = 0,
    this.totalProfitKrw = 0,
    this.profitRateOnDeposit,
    this.incomeKrw = 0,
    this.feeKrw = 0,
  });

  final String? firstDate, lastDate;
  final int txCount;
  final double? holdingsKrw, holdingsUsd;
  final double? usdKrw;
  final String? usdKrwDate;
  final double depositKrw, withdrawalKrw, netDepositKrw;
  final double cashKrw, holdingsTotalKrw, currentAssetKrw;
  final double totalProfitKrw;
  final double? profitRateOnDeposit;
  final double incomeKrw, feeKrw;

  factory StockProfit.fromJson(Map<String, Object?> j) => StockProfit(
    firstDate: j['firstDate'] as String?,
    lastDate: j['lastDate'] as String?,
    txCount: (j['txCount'] as num?)?.toInt() ?? 0,
    holdingsKrw: _d(j['holdingsKrw']),
    holdingsUsd: _d(j['holdingsUsd']),
    usdKrw: _d(j['usdKrw']),
    usdKrwDate: j['usdKrwDate'] as String?,
    depositKrw: _d0(j['depositKrw']),
    withdrawalKrw: _d0(j['withdrawalKrw']),
    netDepositKrw: _d0(j['netDepositKrw']),
    cashKrw: _d0(j['cashKrw']),
    holdingsTotalKrw: _d0(j['holdingsTotalKrw']),
    currentAssetKrw: _d0(j['currentAssetKrw']),
    totalProfitKrw: _d0(j['totalProfitKrw']),
    profitRateOnDeposit: _d(j['profitRateOnDeposit']),
    incomeKrw: _d0(j['incomeKrw']),
    feeKrw: _d0(j['feeKrw']),
  );
}

// 거래 유형 → 화면 이름 (웹 TossAccountPage 와 같게)
const stockTypeLabels = {
  'BUY': '매수',
  'SELL': '매도',
  'DIVIDEND': '배당',
  'DEPOSIT': '입금',
  'WITHDRAWAL': '출금',
  'EXCHANGE_IN': '환전 입금',
  'EXCHANGE_OUT': '환전 출금',
  'INTEREST': '이자',
  'SECURITIES_TRANSFER_IN': '주식 입고',
  'SECURITIES_TRANSFER_OUT': '주식 출고',
};

// 거래내역 한 건 (/api/stock/transactions, 정산일 최신순)
class StockTransaction {
  const StockTransaction({
    required this.id,
    required this.settlementDate,
    required this.type,
    required this.currency,
    this.cancellation = false,
    this.market = '',
    this.transactionTime,
    this.symbol,
    this.name,
    this.quantity,
    this.filledPrice,
    this.amount,
    this.commission,
    this.tax,
    this.netAmount,
  });

  final int id;
  final DateTime settlementDate;
  final DateTime? transactionTime;
  final String type;
  final bool cancellation;
  final String market;
  final String currency;
  final String? symbol, name;
  final double? quantity, filledPrice;
  final double? amount, commission, tax, netAmount;

  String get typeLabel => stockTypeLabels[type] ?? type;

  // 종목 거래가 아니면(입출금 · 환전 · 이자) 유형 이름으로
  String get title => name ?? symbol ?? typeLabel;

  // 거래 시각이 있으면 그걸, 없으면 정산일
  DateTime get when => transactionTime ?? settlementDate;

  // 현금 방향 (부호 표시용): 들어오면 1, 나가면 -1, 주식 입출고 같은 건 0
  int get cashDirection => switch (type) {
    'SELL' || 'DIVIDEND' || 'DEPOSIT' || 'EXCHANGE_IN' || 'INTEREST' => 1,
    'BUY' || 'WITHDRAWAL' || 'EXCHANGE_OUT' => -1,
    _ => 0,
  };

  factory StockTransaction.fromJson(Map<String, Object?> j) => StockTransaction(
    id: (j['id'] as num).toInt(),
    settlementDate: _time(j['settlementDate']) ?? DateTime(1970),
    transactionTime: _time(j['transactionTime']),
    type: (j['transactionType'] as String?) ?? '',
    cancellation: j['cancellation'] == true,
    market: (j['market'] as String?) ?? '',
    currency: (j['currency'] as String?) ?? 'KRW',
    symbol: j['symbol'] as String?,
    name: j['name'] as String?,
    quantity: _d(j['quantity']),
    filledPrice: _d(j['filledPrice']),
    amount: _d(j['amount']),
    commission: _d(j['commission']),
    tax: _d(j['tax']),
    netAmount: _d(j['netAmount']),
  );
}
