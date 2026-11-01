import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lifemetrics_app/main.dart';

void main() {
  void usePhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('첫 실행: 스플래시 후 페르소나 선택 → 저장', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    usePhoneSize(tester);

    await tester.pumpWidget(const MyApp());
    expect(find.text('Lifemetrics'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('어떤 나를 측정할까요?'), findsOneWidget);
    for (final title in ['인간', '애슬리트', '개발자', '증권']) {
      expect(find.text(title), findsOneWidget);
    }

    await tester.tap(find.text('개발자'));
    await tester.pump();
    await tester.tap(find.text('개발자로 시작하기'));
    await tester.pumpAndSettle();

    expect(find.text('개발자 대시보드'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('selected_persona'), 'developer');
  });

  testWidgets('재실행: 저장된 페르소나 홈으로 바로 이동', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'selected_persona': 'investor'});
    usePhoneSize(tester);

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('증권 대시보드'), findsOneWidget);
    expect(find.text('어떤 나를 측정할까요?'), findsNothing);
  });

  testWidgets('애슬리트: 4개 파트 → 하위 메뉴', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'selected_persona': 'athlete'});
    usePhoneSize(tester);

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    for (final title in ['신체 기록', '피트니스 기록', '라이딩 기록', '장비 기록']) {
      expect(find.text(title), findsOneWidget);
    }

    const menus = {
      '신체 기록': ['건강검진', '인바디'],
      '피트니스 기록': ['입력', '기록'],
      '라이딩 기록': ['라이딩 기록', '랜도너스 계획', '투어링 계획', '라이브 라이딩'],
      '장비 기록': ['내 자전거'],
    };
    for (final MapEntry(key: section, value: items) in menus.entries) {
      await tester.tap(find.text(section));
      await tester.pumpAndSettle();
      for (final item in items) {
        // 앱바 제목과 메뉴 이름이 같은 경우(라이딩 기록)가 있어 ListView 안에서만 찾음
        expect(
          find.descendant(of: find.byType(ListView), matching: find.text(item)),
          findsOneWidget,
        );
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('라이딩 기록'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('랜도너스 계획'));
    await tester.pumpAndSettle();
    expect(find.text('준비 중이에요'), findsOneWidget);
  });
}
