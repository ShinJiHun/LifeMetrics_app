import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart'; // ✅ MapLibre import
import '../models/Activity.dart';
import 'package:riding_information_app/cards/ActivityDetailPage.dart';

class ActivityCard extends StatefulWidget {
  final Activity activity;
  final String heroTag;

  const ActivityCard({
    super.key,
    required this.activity,
    required this.heroTag,
  });

  @override
  State<ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends State<ActivityCard> {
  bool isExpanded = false;
  final int previewLength = 50;
  MaplibreMapController? mapController;

  @override
  Widget build(BuildContext context) {
    final String content = widget.activity.content;
    final bool isLongText = content.length > previewLength;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ActivityDetailPage(
              activity: widget.activity,
              heroTag: widget.heroTag,
            ),
          ));
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 날짜 & 기기
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(widget.activity.date,
                      style: Theme.of(context).textTheme.bodySmall),
                  Text(widget.activity.device,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: 8),

              // 제목
              Text(widget.activity.title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),

              // 본문
              Text(
                isExpanded || !isLongText
                    ? content
                    : content.substring(0, previewLength) + "...",
                style: Theme.of(context).textTheme.bodyMedium,
              ),

              if (isLongText)
                TextButton(
                  onPressed: () {
                    setState(() {
                      isExpanded = !isExpanded;
                    });
                  },
                  child: Text(isExpanded ? "접기" : "더보기"),
                ),

              const SizedBox(height: 12),

              // ✅ MapLibre Map Preview
              if (widget.activity.startLatLng != null)
                Hero(
                  tag: widget.heroTag,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: MapLibreMap(
                        styleString: "https://tiles.stadiamaps.com/styles/alidade_smooth/style.json",
                        initialCameraPosition: CameraPosition(
                          target: widget.activity.startLatLng ?? const LatLng(37.5665, 126.9780),
                          zoom: 12,
                        ),
                        zoomGesturesEnabled: false,
                        scrollGesturesEnabled: false,
                        rotateGesturesEnabled: false,
                        tiltGesturesEnabled: false,
                        myLocationEnabled: false,
                        onMapCreated: (controller) async {
                          mapController = controller;
                          _addPolyline(controller);
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// ✅ polyline 표시 함수
  Future<void> _addPolyline(MaplibreMapController controller) async {
    final points = widget.activity.decodedPolylinePoints;
    if (points.isEmpty) return;

    await controller.addLine(LineOptions(
      geometry: points,
      lineColor: "#3B82F6", // indigo-500
      lineWidth: 3.0,
    ));
  }
}
