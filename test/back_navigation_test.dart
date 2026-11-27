import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lifemetrics_app/models/persona.dart';
import 'package:lifemetrics_app/screens/home_screen.dart';
import 'package:lifemetrics_app/screens/persona_select_screen.dart';

void main() {
  testWidgets('홈에서 뒤로가기 → 페르소나 선택, 거기서 한 번 더 → 앱 종료', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen(persona: Persona.developer)),
    );
    await tester.pumpAndSettle();

    // 하위 화면이 열려 있으면 그 화면만 닫힘
    Navigator.of(tester.element(find.byType(Scaffold).first)).push(
      MaterialPageRoute(builder: (_) => const Scaffold(body: Text('하위'))),
    );
    await tester.pumpAndSettle();
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);

    // 홈에서 뒤로가기 → 페르소나 선택 (앱은 그대로)
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(PersonaSelectScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);

    // 페르소나 선택에서 뒤로가기 → 더 돌아갈 곳이 없어 시스템에 맡김(앱 종료)
    expect(await tester.binding.handlePopRoute(), isFalse);
  });
}
