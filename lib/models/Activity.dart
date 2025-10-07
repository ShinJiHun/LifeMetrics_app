import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

class Activity {
  final int id;
  final String date;
  final String device;
  final String title;
  final String content;
  final String? polyline;
  final String? mapUrl;

  Activity({
    required this.id,
    required this.date,
    required this.device,
    required this.title,
    required this.content,
    this.polyline,
    this.mapUrl,
  });

  factory Activity.fromJson(Map<String, dynamic> json) {
    return Activity(
      id: json['id'] as int,
      title: json['activityTitle'] ?? '',
      content: json['activityContent'] ?? '',
      date: json['activityDate'] ?? '',
      device: json['device'] ?? '',
      mapUrl: json['mapUrl'],
      polyline: json['polyline'],
    );
  }

  /// ✅ polyline → List<LatLng> 변환 (MapLibre용)
  List<LatLng> get decodedPolylinePoints {
    if (polyline == null || polyline!.isEmpty) return [];

    try {
      // API 키가 필요 없는 로컬 decode 용도
      final polylinePoints = PolylinePoints(apiKey: '');

      // ✅ 인스턴스 메서드로 호출해야 함
      final List<PointLatLng> result = PolylinePoints.decodePolyline(polyline!);

      return result.map((e) => LatLng(e.latitude, e.longitude)).toList();
    } catch (e) {
      print("❌ Polyline decode error: $e");
      return [];
    }
  }

  /// ✅ 시작점과 끝점 반환
  LatLng? get startLatLng =>
      decodedPolylinePoints.isNotEmpty ? decodedPolylinePoints.first : null;

  LatLng? get endLatLng =>
      decodedPolylinePoints.isNotEmpty ? decodedPolylinePoints.last : null;
}
