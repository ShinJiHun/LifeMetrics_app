// ignore_for_file: use_key_in_widget_constructors

import 'package:flutter/material.dart';

class MyScreen extends StatefulWidget {
  @override
  State<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen> {
  @override
  Widget build(BuildContext context) {
    return Container(
      child: Text("마이 스크린입니다.", style: TextStyle(fontFamily: 'NotoSansKR',fontSize: 20, color: Colors.black)),
    );
  }
}
