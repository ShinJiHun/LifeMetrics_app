import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

import '../models/Activity.dart';

class ActivityDetailPage extends StatefulWidget {
  final Activity activity;
  final String heroTag;

  const ActivityDetailPage({
    super.key,
    required this.activity,
    required this.heroTag,
  });

  @override
  State<ActivityDetailPage> createState() => _ActivityDetailPageState();
}

class _ActivityDetailPageState extends State<ActivityDetailPage> {
  MaplibreMapController? _mapController;
  late final List<LatLng> _route;

  // ✅ 오픈소스 무료 타일 서버 (MapTiler, MapLibre)
  static const String _mapStyleUrl =
      "https://demotiles.maplibre.org/style.json"; // 무료 MapLibre 스타일

  @override
  void initState() {
    super.initState();
    _route = _decodeEncodedPolyline(widget.activity.polyline);
  }

  List<LatLng> _decodeEncodedPolyline(String? encoded) {
    if (encoded == null || encoded.isEmpty) return [];
    final points = PolylinePoints.decodePolyline(encoded);
    return points.map((p) => LatLng(p.latitude, p.longitude)).toList();
  }

  void _onMapCreated(MaplibreMapController controller) async {
    _mapController = controller;

    if (_route.isNotEmpty) {
      // 카메라 이동
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(_boundsFromLatLngList(_route),
            top: 50, bottom: 50, left: 50, right: 50),
      );

      // 경로 Polyline 추가
      await controller.addLine(LineOptions(
        geometry: _route,
        lineColor: "#FF007AFF",
        lineWidth: 4.0,
        lineOpacity: 0.9,
      ));

      // 시작점
      await controller.addSymbol(SymbolOptions(
        geometry: _route.first,
        iconImage: "marker-15",
        textField: "Start",
        textOffset: const Offset(0, 1.5),
      ));

      // 끝점
      await controller.addSymbol(SymbolOptions(
        geometry: _route.last,
        iconImage: "marker-15",
        textField: "End",
        textOffset: const Offset(0, 1.5),
      ));
    }
  }

  LatLngBounds _boundsFromLatLngList(List<LatLng> points) {
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLon = points.first.longitude;
    double maxLon = points.first.longitude;

    for (var p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLon),
      northeast: LatLng(maxLat, maxLon),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasRoute = _route.isNotEmpty;
    final center = hasRoute ? _route.first : const LatLng(37.5665, 126.9780);

    return Scaffold(
      appBar: AppBar(title: Text(widget.activity.title)),
      body: MaplibreMap(
        styleString: 'https://demotiles.maplibre.org/style.json',
        myLocationEnabled: true,        // ✅ 내 위치 표시
        myLocationTrackingMode: MyLocationTrackingMode.tracking, // ✅ 추적 모드 (선택)
        compassEnabled: true,
        initialCameraPosition: CameraPosition(
          target: LatLng(37.5665, 126.9780),
          zoom: 12,
        ),
        onMapCreated: (controller) {
          _mapController = controller;
        },
      )
    );
  }
}
