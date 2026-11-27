import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/persona.dart';
import '../../models/stock.dart';
import '../../services/api_client.dart';
import '../../services/stock_api.dart';
import '../../utils/format.dart';
import '../../widgets/admin_login_dialog.dart';
import '../../widgets/status_message.dart';

// 증권 페르소나: 토스증권 계좌 (웹 TossAccountPage 의 앱 버전, 보기만).
// data_pipeline 이 토스증권에서 받아 온 총 수익 · 계좌 요약 · 수익률 추이 · 보유 종목 · 최근 거래.
// 서버 API 는 관리자 전용이라 처음에 지문 · 비밀번호로 로그인
class StockScreen extends StatefulWidget {
  const StockScreen({super.key, this.api, this.now});

  final StockApi? api;
  final DateTime? now; // 테스트에서 '오늘' 고정용

  @override
  State<StockScreen> createState() => _StockScreenState();
}

// 국내 관례: 이익 빨강, 손실 파랑
const _up = Color(0xFFFF6B6B);
const _down = Color(0xFF5B9BFF);
const _surface = Color(0xFF211E36);
const _muted = Color(0x99FFFFFF);

Color _tone(double? v) => v == null || v == 0
    ? Colors.white
    : v > 0
    ? _up
    : _down;

String _money(double? v, String currency) {
  if (v == null) return '-';
  if (currency == 'USD') {
    final cents = (v.abs() * 100).round();
    final s = '\$${formatThousands(cents ~/ 100)}.'
        '${(cents % 100).toString().padLeft(2, '0')}';
    return v < 0 ? '-$s' : s;
  }
  return '${formatThousands(v)}원';
}

String _signed(double? v, String currency) {
  if (v == null) return '-';
  final sign = v > 0 ? '+' : (v < 0 ? '-' : '');
  return '$sign${_money(v.abs(), currency)}';
}

// 0.0123 → +1.23%
String _pct(double? rate) {
  if (rate == null) return '-';
  return '${rate > 0 ? '+' : ''}${(rate * 100).toStringAsFixed(2)}%';
}

String _qty(double v) {
  if (v == v.roundToDouble()) return formatThousands(v);
  return v.toStringAsFixed(6).replaceFirst(RegExp(r'0+$'), '');
}

// 거래내역 필터 (서버 유형 여러 개를 하나로 묶음). null 은 전체
enum _TxGroup {
  trade('매매', {'BUY', 'SELL'}),
  income('배당·이자', {'DIVIDEND', 'INTEREST'}),
  cash('입출금', {'DEPOSIT', 'WITHDRAWAL'}),
  exchange('환전', {'EXCHANGE_IN', 'EXCHANGE_OUT'});

  const _TxGroup(this.label, this.types);

  final String label;
  final Set<String> types;
}

class _StockScreenState extends State<StockScreen> {
  static final _color = Persona.investor.color;
  static const _txDays = 90; // 최근 거래는 90일치
  static const _txPage = 20;

  late final StockApi _api = widget.api ?? StockApi();

  StockSummary? _summary;
  StockProfit? _profit;
  List<StockTransaction> _txs = const [];
  bool _loading = true;
  bool _needsLogin = false;
  String? _error;

  _TxGroup? _group;
  int _txShown = _txPage;

  @override
  void initState() {
    super.initState();
    _load(askLogin: true);
  }

  Future<void> _load({bool askLogin = false}) async {
    setState(() {
      _loading = _summary == null; // 당겨서 새로고침일 땐 화면을 그대로 두고
      _error = null;
    });
    final today = widget.now ?? DateTime.now();
    try {
      final results = await Future.wait([
        _api.summary(),
        _api.profit(),
        _api.transactions(
          from: today.subtract(const Duration(days: _txDays)),
          to: today,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as StockSummary;
        _profit = results[1] as StockProfit;
        _txs = results[2] as List<StockTransaction>;
        _needsLogin = false;
        _loading = false;
      });
    } on AdminRequiredException {
      if (!mounted) return;
      setState(() {
        _needsLogin = true;
        _loading = false;
      });
      if (askLogin) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _login());
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _login() async {
    if (!mounted) return;
    if (await loginAdminWithDialog(context, _api.loginAdmin)) await _load();
  }

  List<StockTransaction> get _filteredTxs => _group == null
      ? _txs
      : _txs.where((t) => _group!.types.contains(t.type)).toList();

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: _color));
    }
    if (_needsLogin) {
      return StatusMessage(
        icon: Icons.lock_outline,
        title: '관리자 로그인이 필요해요',
        detail: '계좌 정보라 로그인한 뒤에만 볼 수 있어요',
        color: _color,
        action: '로그인',
        onAction: _login,
      );
    }
    if (_error != null && _summary == null) {
      return StatusMessage(
        icon: Icons.cloud_off,
        title: '계좌 정보를 불러오지 못했어요',
        detail: _error,
        color: _color,
        action: '다시 시도',
        onAction: _load,
      );
    }

    final summary = _summary!;
    final latest = summary.latest;
    return RefreshIndicator(
      color: _color,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (_error != null) _ErrorBanner(text: _error!),
          if (_profit != null) _ProfitCard(p: _profit!, accent: _color),
          const SizedBox(height: 12),
          if (latest == null)
            const _Card(child: Text('아직 계좌 스냅샷이 없어요'))
          else ...[
            _AccountCard(s: latest),
            if (summary.history.length >= 2) ...[
              const SizedBox(height: 12),
              _RateTrendCard(history: summary.history, accent: _color),
            ],
          ],
          const SizedBox(height: 20),
          _SectionTitle(
            '보유 종목',
            trailing: '${summary.holdings.length}종목',
          ),
          if (summary.holdings.isEmpty)
            const _Card(child: Text('보유 종목이 없어요'))
          else
            _Card(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, h) in summary.holdings.indexed) ...[
                    if (i > 0) const Divider(height: 1, color: Color(0x14FFFFFF)),
                    _HoldingRow(h: h),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 20),
          _SectionTitle('최근 거래', trailing: '$_txDays일'),
          _txFilter(),
          const SizedBox(height: 8),
          ..._txList(),
        ],
      ),
    );
  }

  Widget _txFilter() {
    Widget chip(String label, _TxGroup? g) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: _group == g,
        showCheckmark: false,
        selectedColor: _color.withValues(alpha: 0.3),
        backgroundColor: _surface,
        side: BorderSide.none,
        labelStyle: const TextStyle(color: Colors.white, fontSize: 13),
        onSelected: (_) => setState(() {
          _group = g;
          _txShown = _txPage;
        }),
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('전체', null),
          for (final g in _TxGroup.values) chip(g.label, g),
        ],
      ),
    );
  }

  List<Widget> _txList() {
    final list = _filteredTxs;
    if (list.isEmpty) {
      return const [_Card(child: Text('이 기간에 거래가 없어요'))];
    }
    final shown = list.take(_txShown).toList();
    return [
      _Card(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (final (i, t) in shown.indexed) ...[
              if (i > 0) const Divider(height: 1, color: Color(0x14FFFFFF)),
              _TxRow(t: t),
            ],
          ],
        ),
      ),
      if (list.length > shown.length)
        TextButton(
          onPressed: () => setState(() => _txShown += _txPage),
          child: Text(
            '더 보기 (${list.length - shown.length}건 남음)',
            style: TextStyle(color: _color),
          ),
        ),
    ];
  }
}

// ── 공통 ──────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.accent,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: accent == null
            ? null
            : Border(top: BorderSide(color: accent!, width: 3)),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: child,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          if (trailing != null)
            Text(trailing!, style: const TextStyle(color: _muted, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x33FF6B6B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white)),
    );
  }
}

// 왼쪽 이름, 오른쪽 값 한 줄 (총 수익 계산 풀이)
class _CalcRow extends StatelessWidget {
  const _CalcRow(this.label, this.value, {this.hint, this.bold = true});

  final String label;
  final String value;
  final String? hint;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                text: label,
                children: [
                  if (hint != null)
                    TextSpan(
                      text: '  $hint',
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                ],
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 총 수익 ──────────────────────────────────────

class _ProfitCard extends StatelessWidget {
  const _ProfitCard({required this.p, required this.accent});

  final StockProfit p;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return _Card(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💰 총 수익', style: TextStyle(color: _muted, fontSize: 13)),
          const SizedBox(height: 6),
          Text(
            _signed(p.totalProfitKrw, 'KRW'),
            style: TextStyle(
              color: _tone(p.totalProfitKrw),
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (p.profitRateOnDeposit != null)
            Text(
              '넣은 돈 대비 ${_pct(p.profitRateOnDeposit)}',
              style: TextStyle(color: _tone(p.profitRateOnDeposit), fontSize: 13),
            ),
          const SizedBox(height: 12),
          _CalcRow(
            '지금 자산',
            _money(p.currentAssetKrw, 'KRW'),
            hint: '보유 평가 + 현금',
          ),
          _CalcRow(
            '  보유 종목 평가',
            _money(p.holdingsTotalKrw, 'KRW'),
            bold: false,
            hint: (p.holdingsUsd ?? 0) != 0
                ? '달러 ${_money(p.holdingsUsd, 'USD')} 포함'
                : null,
          ),
          _CalcRow(
            '  현금(추정)',
            _money(p.cashKrw, 'KRW'),
            bold: false,
          ),
          _CalcRow(
            '− 넣은 돈',
            _money(p.netDepositKrw, 'KRW'),
            hint: '입금 − 출금',
          ),
          const Divider(color: Color(0x33FFFFFF)),
          _CalcRow('= 총 수익', _signed(p.totalProfitKrw, 'KRW')),
          const SizedBox(height: 8),
          Text(
            [
              '${p.firstDate ?? '-'} ~ ${p.lastDate ?? '-'} · 거래 ${formatThousands(p.txCount)}건',
              if (p.usdKrw != null)
                '달러는 ${formatThousands(p.usdKrw!)}원(${p.usdKrwDate ?? '-'})으로 환산',
            ].join('\n'),
            style: const TextStyle(color: _muted, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }
}

// ── 계좌 요약 ──────────────────────────────────────

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.s});

  final AccountSnapshot s;

  @override
  Widget build(BuildContext context) {
    Widget tile(String flag, String c) {
      final krw = c == 'KRW';
      final evalAmt = krw ? s.evalKrw : s.evalUsd;
      final pnl = krw ? s.pnlKrw : s.pnlUsd;
      final daily = krw ? s.dailyPnlKrw : s.dailyPnlUsd;
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$flag 평가금액', style: const TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _money(evalAmt, c),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '손익 ${_signed(pnl, c)}',
              style: TextStyle(color: _tone(pnl), fontSize: 12),
            ),
            Text(
              '오늘 ${_signed(daily, c)}',
              style: TextStyle(color: _tone(daily), fontSize: 12),
            ),
          ],
        ),
      );
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('계좌 요약', style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(
                '${formatShortDate(s.snapshotAt)} ${s.sessionLabel}'
                '${s.accountSuffix.isEmpty ? '' : ' · …${s.accountSuffix}'}',
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tile('🇰🇷', 'KRW'),
              const SizedBox(width: 12),
              tile('🇺🇸', 'USD'),
            ],
          ),
          const Divider(height: 24, color: Color(0x22FFFFFF)),
          Row(
            children: [
              const Text('전체 수익률', style: TextStyle(color: _muted, fontSize: 12)),
              const SizedBox(width: 8),
              Text(
                _pct(s.pnlRate),
                style: TextStyle(
                  color: _tone(s.pnlRate),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '비용 반영 ${_pct(s.pnlRateAfterCost)} · 오늘 ${_pct(s.dailyPnlRate)}',
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── 수익률 추이 ──────────────────────────────────────

// 장 마감 스냅샷마다의 전체 수익률(%). 서버는 최신순이라 뒤집어서 그림
class _RateTrendCard extends StatelessWidget {
  const _RateTrendCard({required this.history, required this.accent});

  final List<AccountSnapshot> history;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final points = history.reversed.where((s) => s.pnlRate != null).toList();
    if (points.length < 2) return const SizedBox.shrink();
    final values = [for (final s in points) s.pnlRate! * 100];
    final lo = values.reduce(math.min), hi = values.reduce(math.max);
    final pad = math.max((hi - lo) * 0.15, 0.5);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('수익률 추이', style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(
                '${formatShortDate(points.first.snapshotAt)} ~ '
                '${formatShortDate(points.last.snapshotAt)}',
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (values.length - 1).toDouble(),
                minY: lo - pad,
                maxY: hi + pad,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: v.abs() < 1e-9
                        ? Colors.white.withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.06),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  bottomTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      minIncluded: false,
                      maxIncluded: false,
                      getTitlesWidget: (v, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text(
                          '${formatNum(v)}%',
                          style: const TextStyle(color: _muted, fontSize: 10),
                        ),
                      ),
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF2E2A4A),
                    getTooltipItems: (spots) => [
                      for (final s in spots)
                        LineTooltipItem(
                          '${formatShortDate(points[s.x.toInt()].snapshotAt)} '
                          '${points[s.x.toInt()].sessionLabel}\n'
                          '${s.y >= 0 ? '+' : ''}${s.y.toStringAsFixed(2)}%',
                          const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (final (i, v) in values.indexed)
                        FlSpot(i.toDouble(), v),
                    ],
                    isCurved: true,
                    preventCurveOverShooting: true,
                    color: accent,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: accent.withValues(alpha: 0.12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 보유 종목 · 거래 ──────────────────────────────────────

class _HoldingRow extends StatelessWidget {
  const _HoldingRow({required this.h});

  final Holding h;

  @override
  Widget build(BuildContext context) {
    final c = h.currency;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  h.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_qty(h.quantity)}주 · 평균 ${_money(h.avgPrice, c)}',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                Text(
                  '현재 ${_money(h.currentPrice, c)} · ${h.market}',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _money(h.evalAmount, c),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                '${_signed(h.pnl, c)} (${_pct(h.pnlRate)})',
                style: TextStyle(color: _tone(h.pnl), fontSize: 12),
              ),
              Text(
                '오늘 ${_pct(h.dailyPnlRate)}',
                style: TextStyle(color: _tone(h.dailyPnlRate), fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TxRow extends StatelessWidget {
  const _TxRow({required this.t});

  final StockTransaction t;

  @override
  Widget build(BuildContext context) {
    final amount = t.netAmount ?? t.amount;
    final hasTrade = t.quantity != null && t.filledPrice != null;
    final typeColor = switch (t.type) {
      'BUY' => _up,
      'SELL' => _down,
      _ => _muted,
    };
    return Opacity(
      opacity: t.cancellation ? 0.45 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Text(
                formatShortDate(t.when),
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      decoration: t.cancellation
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  Text(
                    [
                      t.typeLabel,
                      if (hasTrade)
                        '${_qty(t.quantity!)}주 × ${_money(t.filledPrice, t.currency)}',
                      if (t.cancellation) '취소',
                    ].join(' · '),
                    style: TextStyle(color: typeColor, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              amount == null
                  ? '-'
                  : '${const {1: '+', -1: '-'}[t.cashDirection] ?? ''}'
                        '${_money(amount.abs(), t.currency)}',
              style: const TextStyle(
                fontSize: 13,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
