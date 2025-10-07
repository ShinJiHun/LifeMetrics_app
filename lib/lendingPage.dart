import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:riding_information_app/mainPage.dart';

class LendingPage extends StatefulWidget {
  const LendingPage({Key? key}) : super(key: key);

  @override
  State<LendingPage> createState() => _LendingPageState();
}

class _LendingPageState extends State<LendingPage> {
  @override
  void initState() {
    Timer(Duration(seconds: 3), () {
      Get.to(MainPage());
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            child: Image.asset('assets/image/Riding.png', fit: BoxFit.cover),
          ),
          Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            child: Image.asset('assets/image/Riding.png', fit: BoxFit.cover),
          ),
          CircularProgressIndicator()
        ],
      ),
    );
  }
}
