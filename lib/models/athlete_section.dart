import 'package:flutter/material.dart';

import '../screens/athlete/body/inbody_screen.dart';
import '../screens/athlete/body/samsung_health_screen.dart';
import '../screens/athlete/fitness/workout_history_screen.dart';
import '../screens/athlete/fitness/workout_input_screen.dart';
import '../screens/athlete/riding/ride_feed_screen.dart';

class SectionMenu {
  const SectionMenu({
    required this.title,
    required this.description,
    required this.icon,
    this.builder,
  });

  final String title;
  final String description;
  final IconData icon;
  final Widget Function()? builder; // null 이면 준비 중 화면
}

// 애슬리트 페르소나의 4개 파트와 파트별 하위 메뉴
enum AthleteSection {
  body(
    title: '신체 기록',
    subtitle: '건강검진 · 인바디 · 삼성헬스',
    description: '몸 상태 변화를 한눈에 확인해요',
    icon: Icons.monitor_heart,
    color: Color(0xFFE94F64),
    menus: [
      SectionMenu(
        title: '건강검진',
        description: '검진 결과와 주요 수치를 모아봐요',
        icon: Icons.medical_information,
      ),
      SectionMenu(
        title: '인바디',
        description: '체중 · 골격근량 · 체지방률 추이',
        icon: Icons.accessibility_new,
        builder: InbodyScreen.new,
      ),
      SectionMenu(
        title: '삼성헬스',
        description: '걸음 · 수면 · 심박 (헬스 커넥트)',
        icon: Icons.watch,
        builder: SamsungHealthScreen.new,
      ),
    ],
  ),
  fitness(
    title: '피트니스 기록',
    subtitle: '입력 · 기록',
    description: '웨이트와 트레이닝을 기록해요',
    icon: Icons.fitness_center,
    color: Color(0xFFFF7A45),
    menus: [
      SectionMenu(
        title: '입력',
        description: '오늘의 운동을 입력해요',
        icon: Icons.edit_note,
        builder: WorkoutInputScreen.new,
      ),
      SectionMenu(
        title: '기록',
        description: '지난 운동 기록을 돌아봐요',
        icon: Icons.history,
        builder: WorkoutHistoryScreen.new,
      ),
    ],
  ),
  riding(
    title: '라이딩 기록',
    subtitle: '기록 · 랜도너스 · 투어링',
    description: '라이딩과 장거리 계획을 관리해요',
    icon: Icons.directions_bike,
    color: Color(0xFF2EC4B6),
    menus: [
      SectionMenu(
        title: '라이딩 기록',
        description: '거리 · 시간 · 획득고도를 기록해요',
        icon: Icons.timeline,
        builder: RideFeedScreen.new,
      ),
      SectionMenu(
        title: '랜도너스 계획',
        description: '브레베 코스와 컨트롤 포인트 계획',
        icon: Icons.flag,
      ),
      SectionMenu(
        title: '투어링 계획',
        description: '여행 일정과 숙박 · 보급 계획',
        icon: Icons.map,
      ),
      SectionMenu(
        title: '라이브 라이딩',
        description: '지금 달리는 라이딩을 실시간으로',
        icon: Icons.sensors,
      ),
    ],
  ),
  gear(
    title: '장비 기록',
    subtitle: '내 자전거',
    description: '장비 스펙과 관리 이력을 남겨요',
    icon: Icons.build,
    color: Color(0xFF7C6CF2),
    menus: [
      SectionMenu(
        title: '내 자전거',
        description: '보유 자전거와 부품 정보',
        icon: Icons.pedal_bike,
      ),
    ],
  );

  const AthleteSection({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.color,
    required this.menus,
  });

  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final Color color;
  final List<SectionMenu> menus;
}
