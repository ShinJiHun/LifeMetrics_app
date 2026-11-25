import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';
import 'services/health_auto_sync.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  HealthAutoSync.initialize().catchError(
    (Object e) => debugPrint('자동 동기화 초기화 실패: $e'),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const _background = Color(0xFF15122B);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lifemetrics',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF7C6CF2),
        scaffoldBackgroundColor: _background,
      ),
      // 모든 화면(다이얼로그 · 바텀시트 포함)을 안드로이드 하단 버튼(뒤로 · 홈 · 최근 앱)
      // 또는 제스처 바 위에만 그림. 안드로이드 15+ 는 기본이 화면 끝까지(edge-to-edge)라
      // 하단 바 뒤로 내용이 들어가던 것을 여기서 한 번에 막음. 위쪽은 각 화면 AppBar 가 처리
      builder: (context, child) => ColoredBox(
        color: _background,
        child: SafeArea(
          top: false,
          left: false,
          right: false,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
