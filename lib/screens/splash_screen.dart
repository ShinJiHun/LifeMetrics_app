import 'package:flutter/material.dart';

import '../models/persona.dart';
import '../services/persona_store.dart';
import 'home_screen.dart';
import 'persona_select_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
  );

  late final Animation<double> _scale = Tween(begin: 0.85, end: 1.0).animate(
    CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack),
    ),
  );

  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.2, 1.0, curve: Curves.easeInOut),
  );

  @override
  void initState() {
    super.initState();
    _start();
  }

  // 로딩 애니메이션과 저장된 페르소나 조회를 함께 진행
  Future<void> _start() async {
    final saved = PersonaStore.load();
    await _controller.forward();
    _goNext(await saved);
  }

  void _goNext(Persona? saved) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, _, _) => saved == null
            ? const PersonaSelectScreen()
            : HomeScreen(persona: saved),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF15122B), Color(0xFF2A2350)],
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7C6CF2), Color(0xFF2EC4B6)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7C6CF2)
                                .withValues(alpha: 0.5),
                            blurRadius: 32,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.insights,
                        size: 52,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Lifemetrics',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '나의 삶을 숫자로 읽다',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 48),
                    SizedBox(
                      width: 160,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _progress.value,
                          minHeight: 4,
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                          valueColor: const AlwaysStoppedAnimation(
                            Color(0xFF2EC4B6),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
