import 'package:flutter/material.dart';

import '../../../models/athlete_section.dart';
import '../../../models/ride.dart';
import '../../../services/api_client.dart';
import '../../../services/ride_api.dart';
import '../../../utils/format.dart';
import 'ride_detail_screen.dart';
import 'ride_route_map.dart';

// 라이딩 기록: 스트라바 피드처럼 최신 라이딩부터 카드로
class RideFeedScreen extends StatefulWidget {
  const RideFeedScreen({super.key, this.api});

  final RideApi? api;

  @override
  State<RideFeedScreen> createState() => _RideFeedScreenState();
}

class _RideFeedScreenState extends State<RideFeedScreen> {
  static final _color = AthleteSection.riding.color;

  late final RideApi _api = widget.api ?? RideApi();

  List<Ride>? _rides; // 최신순, 로딩 중엔 null
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rides = await _api.fetchRides();
      if (mounted) {
        setState(() {
          _rides = rides;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _retry() async {
    setState(() {
      _error = null;
      _rides = null;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('라이딩 기록'),
      ),
      body: switch ((_rides, _error)) {
        (null, final String error) => _Message(
          icon: Icons.cloud_off,
          text: error,
          color: _color,
          onRetry: _retry,
        ),
        (null, _) => const Center(child: CircularProgressIndicator()),
        (final List<Ride> rides, _) => RefreshIndicator(
          onRefresh: _load,
          child: rides.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 120),
                    _Message(
                      icon: Icons.directions_bike,
                      text: '아직 라이딩 기록이 없어요',
                      color: _color,
                    ),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: rides.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (_, i) => RideCard(
                    key: ValueKey(rides[i].id),
                    ride: rides[i],
                    api: _api,
                  ),
                ),
        ),
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    required this.color,
    this.onRetry,
  });

  final IconData icon;
  final String text;
  final Color color;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: color),
            const SizedBox(height: 16),
            Text(
              text,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                style: FilledButton.styleFrom(backgroundColor: color),
                icon: const Icon(Icons.refresh),
                label: const Text('다시 시도'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// 피드 카드: 머리글 → 제목 → 핵심 기록 3개 → 경로 지도 → 보조 기록
class RideCard extends StatelessWidget {
  const RideCard({super.key, required this.ride, this.api});

  static const routeColor = Color(0xFFFC4C02); // 스트라바 오렌지

  final Ride ride;
  final RideApi? api; // 상세 화면에 넘김

  @override
  Widget build(BuildContext context) {
    final r = ride;
    final color = AthleteSection.riding.color;
    final muted = Colors.white.withValues(alpha: 0.55);
    final extras = [
      if (r.avgPower != null) ('평균 파워', '${r.avgPower!.round()} W'),
      if (r.avgHeartRate != null) ('평균 심박', '${r.avgHeartRate!.round()} bpm'),
      if (r.calories != null) ('칼로리', '${formatThousands(r.calories!)} kcal'),
      if (r.relativeEffort != null) ('상대적 노력', '${r.relativeEffort}'),
    ];

    // 카드 어디를 눌러도 상세로. 지도가 탭을 먹지 않게 InkWell 을 맨 위에 덮음
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Stack(
        children: [
          _content(r, color, muted, extras),
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RideDetailScreen(ride: r, api: api),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(
    Ride r,
    Color color,
    Color muted,
    List<(String, String)> extras,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color.withValues(alpha: 0.2),
                child: Icon(Icons.directions_bike, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatDateTime(r.startTime),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (r.bikeLabel != null)
                      Text(
                        r.bikeLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                  ],
                ),
              ),
              if (r.rideType != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    r.rideType!.label,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Text(
            r.title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Row(
            children: [
              _Stat(
                label: '거리',
                value: r.distanceMeters == null
                    ? '-'
                    : '${(r.distanceMeters! / 1000).toStringAsFixed(2)} km',
              ),
              _Stat(
                label: '획득고도',
                value: r.elevationGain == null
                    ? '-'
                    : '${formatThousands(r.elevationGain!)} m',
              ),
              _Stat(
                label: '시간',
                value: r.movingSeconds == null
                    ? '-'
                    : formatDuration(r.movingSeconds!),
              ),
            ],
          ),
        ),
        // 피드에서는 스크롤을 막지 않도록 정지 지도
        AspectRatio(
          aspectRatio: 16 / 10,
          child: RideRouteMap(route: r.route, color: routeColor),
        ),
        if (extras.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                for (final (label, value) in extras)
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$label ',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                        TextSpan(
                          text: value,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
