import 'package:flutter/material.dart';
import 'mainPage.dart'; // ✅ mainPage.dart 불러오기

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RidingApp());
}

class RidingApp extends StatelessWidget {
  const RidingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '라이딩그램',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blueGrey,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const MainPage(), // ✅ 여기만 유지
    );
  }
}
