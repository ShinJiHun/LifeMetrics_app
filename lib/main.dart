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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lifemetrics',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF7C6CF2),
        scaffoldBackgroundColor: const Color(0xFF15122B),
      ),
      home: const SplashScreen(),
    );
  }
}
