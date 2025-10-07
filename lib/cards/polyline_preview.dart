import 'dart:ui';
import 'package:flutter/material.dart';

class LatLng {
  final double lat;
  final double lng;
  const LatLng(this.lat, this.lng);
}

/// Google Encoded Polyline → List<LatLng>
List<LatLng> decodePolyline(String encoded) {
  int index = 0, len = encoded.length;
  int lat = 0, lng = 0;
  final List<LatLng> pts = [];
  while (index < len) {
    int b, shift = 0, result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    final dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
    lat += dlat;

    shift = 0; result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    final dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
    lng += dlng;

    pts.add(LatLng(lat / 1e5, lng / 1e5)); // 필요하면 1e6로 조정
  }
  return pts;
}

class PolylinePreview extends StatelessWidget {
  final String? encodedPolyline;
  final double strokeWidth;
  final Color strokeColor;
  final Color backgroundColor;
  final EdgeInsets padding;
  final bool drawStartEnd;

  const PolylinePreview({
    super.key,
    required this.encodedPolyline,
    this.strokeWidth = 3.0,
    this.strokeColor = Colors.black87,
    this.backgroundColor = const Color(0xFFF5F5F5),
    this.padding = const EdgeInsets.all(12),
    this.drawStartEnd = true,
  });

  @override
  Widget build(BuildContext context) {
    if (encodedPolyline == null || encodedPolyline!.isEmpty) {
      return Container(color: backgroundColor);
    }
    final points = decodePolyline(encodedPolyline!);
    if (points.length < 2) {
      return Container(color: backgroundColor);
    }
    return CustomPaint(
      painter: _PolylinePainter(
        points: points,
        strokeWidth: strokeWidth,
        strokeColor: strokeColor,
        backgroundColor: backgroundColor,
        padding: padding,
        drawStartEnd: drawStartEnd,
      ),
      // 크기는 부모(예: AspectRatio)가 정해줍니다.
    );
  }
}

class _PolylinePainter extends CustomPainter {
  final List<LatLng> points;
  final double strokeWidth;
  final Color strokeColor;
  final Color backgroundColor;
  final EdgeInsets padding;
  final bool drawStartEnd;

  _PolylinePainter({
    required this.points,
    required this.strokeWidth,
    required this.strokeColor,
    required this.backgroundColor,
    required this.padding,
    required this.drawStartEnd,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = backgroundColor;
    canvas.drawRect(Offset.zero & size, bg);

    // 경계 계산
    double minLat = points.first.lat, maxLat = points.first.lat;
    double minLng = points.first.lng, maxLng = points.first.lng;
    for (final p in points) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lng < minLng) minLng = p.lng;
      if (p.lng > maxLng) maxLng = p.lng;
    }

    final drawW = size.width - padding.horizontal;
    final drawH = size.height - padding.vertical;
    final dx = (maxLng - minLng).abs().clamp(1e-9, double.infinity);
    final dy = (maxLat - minLat).abs().clamp(1e-9, double.infinity);

    // 비율 유지 스케일
    final scale = (dx == 0 || dy == 0)
        ? 1.0
        : (drawW / dx).clamp(0, double.infinity)
            .clamp(0, double.infinity)
            .clamp(0, double.infinity);
    final scaleY = drawH / dy;
    final s = scale < scaleY ? scale : scaleY;

    // 중심 정렬 오프셋 (북쪽이 위이므로 lat은 반전)
    double contentW = dx * s;
    double contentH = dy * s;
    final left = padding.left + (drawW - contentW) / 2;
    final top = padding.top + (drawH - contentH) / 2;

    // Path 구성
    final path = Path();
    Offset toCanvas(LatLng p) {
      final x = left + (p.lng - minLng) * s;
      final y = top + (maxLat - p.lat) * s; // 위쪽이 북쪽
      return Offset(x, y);
    }

    path.moveTo(toCanvas(points.first).dx, toCanvas(points.first).dy);
    for (int i = 1; i < points.length; i++) {
      final o = toCanvas(points[i]);
      path.lineTo(o.dx, o.dy);
    }

    // 스트로크
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = strokeColor
      ..isAntiAlias = true;

    // 외곽 그 shadow 느낌 (선택)
    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withOpacity(0.9)
      ..isAntiAlias = true;

    canvas.drawPath(path, halo);
    canvas.drawPath(path, paint);

    if (drawStartEnd) {
      final start = toCanvas(points.first);
      final end = toCanvas(points.last);
      final startPaint = Paint()..color = const Color(0xFF2E7D32);
      final endPaint = Paint()..color = const Color(0xFFC62828);
      canvas.drawCircle(start, strokeWidth + 3, startPaint);
      canvas.drawCircle(end, strokeWidth + 3, endPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PolylinePainter old) {
    return old.points != points ||
        old.strokeWidth != strokeWidth ||
        old.strokeColor != strokeColor ||
        old.backgroundColor != backgroundColor ||
        old.padding != padding ||
        old.drawStartEnd != drawStartEnd;
  }
}
