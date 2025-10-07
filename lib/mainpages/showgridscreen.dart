// ignore_for_file: use_key_in_widget_constructors
import 'package:flutter/material.dart';

class ShowGridScreen extends StatefulWidget {
  @override
  State<ShowGridScreen> createState() => _ShowGridScreenState();
}

class _ShowGridScreenState extends State<ShowGridScreen> {
  @override
  Widget build(BuildContext context) {
    return Container(
      child: Text(
        "모아보기 스크린입니다",
        style: TextStyle(
          fontFamily: 'NotoSansKR',
          fontSize: 20,
          color: Colors.black,
        ),
      ),
    );
  }
}
