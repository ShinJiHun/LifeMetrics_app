import 'package:flutter/material.dart';

class MyLikeScreen extends StatefulWidget {
  @override
  State<MyLikeScreen> createState() => _MyLikeScreenState();
}

class _MyLikeScreenState extends State<MyLikeScreen> {
  @override
  Widget build(BuildContext context) {
    return Container(
      child: Text("종아요. 스크린입니다.", style: TextStyle(fontFamily: 'NotoSansKR',fontSize: 20, color: Colors.black)),
    );
  }
}
