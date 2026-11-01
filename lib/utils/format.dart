String formatDate(DateTime d) =>
    '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

String formatShortDate(DateTime d) => '${d.month}/${d.day}';

// 소수점 한 자리, .0 은 생략
String formatNum(double v) {
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

// 1403 → 1,403
String formatThousands(num v) => v.round().toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);

// 20009초 → 5시간 33분, 1시간 미만은 분만
String formatDuration(int seconds) {
  final h = seconds ~/ 3600, m = seconds % 3600 ~/ 60;
  return h > 0 ? '$h시간 $m분' : '$m분';
}

// 2026년 9월 20일 오후 4:35
String formatDateTime(DateTime d) {
  final pm = d.hour >= 12;
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${d.year}년 ${d.month}월 ${d.day}일 ${pm ? '오후' : '오전'} '
      '$h:${d.minute.toString().padLeft(2, '0')}';
}

// 3150초 → 52:30, 1시간 이상은 1:05:12
String formatClock(int seconds) {
  final h = seconds ~/ 3600, m = seconds % 3600 ~/ 60, s = seconds % 60;
  final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
  return '${h > 0 ? '$h:' : ''}$mm:${s.toString().padLeft(2, '0')}';
}
