// 서버 activity.ride_type
enum RideType {
  touring('TOURING', '투어링'),
  brevet('BREVET', '브레베'),
  permanent('PERMANENT', '퍼머넌트');

  const RideType(this.code, this.label);

  final String code;
  final String label;

  static RideType? fromCode(String? code) {
    for (final t in values) {
      if (t.code == code) return t;
    }
    return null;
  }
}

// GET /api/activity/list 의 라이딩 1건
class Ride {
  Ride({
    required this.id,
    required this.startTime,
    this.name,
    this.distanceMeters,
    this.movingSeconds,
    this.elevationGain,
    this.avgPower,
    this.avgHeartRate,
    this.calories,
    this.relativeEffort,
    this.bikeLabel,
    this.rideType,
    this.polyline,
  });

  final int id;
  final DateTime startTime; // 로컬 시각
  final String? name;
  final double? distanceMeters;
  final int? movingSeconds;
  final double? elevationGain; // 획득고도 (m)
  final double? avgPower; // W
  final double? avgHeartRate; // bpm
  final int? calories;
  final int? relativeEffort;
  final String? bikeLabel;
  final RideType? rideType;
  final String? polyline; // Google encoded polyline

  // 이름이 없으면 스트라바처럼 출발 시간대로 제목을 붙임
  String get title {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    final h = startTime.hour;
    final part = h >= 5 && h < 11
        ? '아침'
        : h >= 11 && h < 14
        ? '점심'
        : h >= 14 && h < 18
        ? '오후'
        : h >= 18 && h < 22
        ? '저녁'
        : '야간';
    return '$part 라이딩';
  }

  // 경로 좌표 (위도, 경도). 처음 쓸 때 한 번만 디코드
  late final List<(double, double)> route = decodePolyline(polyline ?? '');

  factory Ride.fromJson(Map<String, dynamic> json) => Ride(
    id: (json['id'] as num).toInt(),
    startTime: parseServerTime(json['startTime'] as String),
    name: json['name'] as String?,
    distanceMeters: (json['totalDistance'] as num?)?.toDouble(),
    movingSeconds: (json['movingTime'] as num?)?.toInt(),
    elevationGain: (json['totalAscent'] as num?)?.toDouble(),
    avgPower: json['hasPower'] == false
        ? null
        : (json['avgPower'] as num?)?.toDouble(),
    avgHeartRate: (json['avgHeartRate'] as num?)?.toDouble(),
    calories: (json['calories'] as num?)?.toInt(),
    relativeEffort: (json['relativeEffort'] as num?)?.toInt(),
    bikeLabel: (json['gearContext'] as Map?)?['bikeLabel'] as String?,
    rideType: RideType.fromCode(json['rideType'] as String?),
    polyline: json['polyline'] as String?,
  );
}

// 서버가 한국 시각에 'Z'(UTC)만 붙여 보내므로 'Z'는 떼고 벽시계 시각으로 읽음.
// 서버가 +09:00 같은 실제 오프셋을 보내게 고쳐지면 그 값대로 변환
DateTime parseServerTime(String s) => s.endsWith('Z')
    ? DateTime.parse(s.substring(0, s.length - 1))
    : DateTime.parse(s).toLocal();

// Google encoded polyline → (위도, 경도) 목록. 깨진 입력은 읽은 데까지만
List<(double, double)> decodePolyline(String encoded) {
  final points = <(double, double)>[];
  var index = 0, lat = 0, lng = 0;

  int? next() {
    var result = 0, shift = 0;
    while (index < encoded.length) {
      final b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
      if (b < 0x20) return (result & 1) != 0 ? ~(result >> 1) : result >> 1;
    }
    return null;
  }

  while (index < encoded.length) {
    final dLat = next(), dLng = next();
    if (dLat == null || dLng == null) break;
    lat += dLat;
    lng += dLng;
    points.add((lat / 1e5, lng / 1e5));
  }
  return points;
}
