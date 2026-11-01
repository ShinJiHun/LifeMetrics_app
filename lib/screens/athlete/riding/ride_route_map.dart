import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// Mapbox 공개 토큰(pk.)은 --dart-define-from-file=env.json 으로 넘김
const _mapboxToken = String.fromEnvironment('MAPBOX_TOKEN');
const _startColor = Color(0xFF5DCAA5);

// 지도 타일 주소와 출처 표기 (앱의 어두운 테마에 맞춘 다크 스타일).
// 토큰이 없으면 null: 키 없이 받을 수 있는 무료 다크 타일이 없어 지도 없이 경로만 그림
typedef MapTiles = ({String url, String attribution});

MapTiles? mapTilesFor(String mapboxToken) => mapboxToken.isEmpty
    ? null
    : (
        url:
            'https://api.mapbox.com/styles/v1/mapbox/dark-v11/tiles/256/'
            '{z}/{x}/{y}{r}?access_token=${Uri.encodeQueryComponent(mapboxToken)}',
        attribution: '© Mapbox © OpenStreetMap',
      );

final _tiles = mapTilesFor(_mapboxToken);

// 라이딩 경로를 지도 위에 그림. interactive 가 false 면 피드용 정지 지도
class RideRouteMap extends StatefulWidget {
  const RideRouteMap({
    super.key,
    required this.route,
    required this.color,
    this.interactive = false,
    this.tileProvider,
  });

  final List<(double, double)> route; // (위도, 경도)
  final Color color;
  final bool interactive;
  final TileProvider? tileProvider; // 테스트에서 네트워크 대신 쓸 타일

  @override
  State<RideRouteMap> createState() => _RideRouteMapState();
}

class _RideRouteMapState extends State<RideRouteMap> {
  static const _maxPoints = 1500;

  late List<LatLng> _points = _thin(widget.route);

  @override
  void didUpdateWidget(RideRouteMap old) {
    super.didUpdateWidget(old);
    if (old.route != widget.route) _points = _thin(widget.route);
  }

  // 수만 개 점을 그대로 그리면 느려서 솎아냄 (끝점은 항상 포함)
  static List<LatLng> _thin(List<(double, double)> route) {
    final step = math.max(1, route.length ~/ _maxPoints);
    return [
      for (var i = 0; i < route.length; i += step)
        LatLng(route[i].$1, route[i].$2),
      if (route.isNotEmpty && (route.length - 1) % step != 0)
        LatLng(route.last.$1, route.last.$2),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final pts = _points;
    if (pts.length < 2) {
      return Container(
        color: const Color(0xFF1C1934),
        alignment: Alignment.center,
        child: Icon(
          Icons.map_outlined,
          color: Colors.white.withValues(alpha: 0.2),
          size: 40,
        ),
      );
    }

    final tiles = _tiles;
    return FlutterMap(
      options: MapOptions(
        backgroundColor: const Color(0xFF1C1934),
        initialCameraFit: CameraFit.coordinates(
          coordinates: pts,
          padding: const EdgeInsets.all(28),
        ),
        interactionOptions: InteractionOptions(
          flags: widget.interactive
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
      ),
      children: [
        if (tiles != null)
          TileLayer(
            urlTemplate: tiles.url,
            retinaMode: RetinaMode.isHighDensity(context),
            userAgentPackageName: 'com.example.lifemetrics_app',
            tileProvider: widget.tileProvider,
          ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: pts,
              color: widget.color,
              strokeWidth: 3.5,
              borderColor: Colors.black.withValues(alpha: 0.4),
              borderStrokeWidth: 1,
            ),
          ],
        ),
        CircleLayer(
          circles: [_dot(pts.last, widget.color), _dot(pts.first, _startColor)],
        ),
        // 지도 데이터 출처 표기 (SimpleAttributionWidget 은 좁은 카드에서 넘침)
        if (tiles != null)
          Align(
            alignment: Alignment.bottomRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              color: Colors.black.withValues(alpha: 0.4),
              child: Text(
                tiles.attribution,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 9,
                ),
              ),
            ),
          ),
      ],
    );
  }

  static CircleMarker _dot(LatLng p, Color c) => CircleMarker(
    point: p,
    radius: 5,
    color: c,
    borderColor: Colors.white,
    borderStrokeWidth: 2,
  );
}

// 피드 카드의 지도를 누르면 여는 전체 화면 지도
class RideMapScreen extends StatelessWidget {
  const RideMapScreen({
    super.key,
    required this.title,
    required this.route,
    required this.color,
  });

  final String title;
  final List<(double, double)> route;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: RideRouteMap(route: route, color: color, interactive: true),
    );
  }
}
