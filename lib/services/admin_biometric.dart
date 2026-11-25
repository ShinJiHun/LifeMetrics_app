import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'api_client.dart';

// 지문(생체) 인증으로 관리자 로그인.
// 비밀번호로 한 번 로그인하면 서버가 준 관리자 쿠키(30일짜리 서명 토큰)를 폰 보안 저장소
// (안드로이드 키스토어로 암호화)에 보관하고, 다음부터는 지문이 맞을 때만 꺼내 씀.
// 비밀번호 자체는 저장하지 않음. 쿠키가 만료되거나 서버 비밀번호가 바뀌면 지우고 다시 비밀번호로.
// 지문을 못 쓰는 기기 · 테스트(플러그인 없음)에서는 모든 동작이 조용히 '안 됨'으로 끝남
class AdminBiometric {
  AdminBiometric._();

  static const _key = 'admin_cookie';
  static final _auth = LocalAuthentication();
  static const _storage = FlutterSecureStorage();

  static bool _hooked = false;

  // 서버가 저장해 둔 쿠키를 거절하면 저장소에서도 지움 (안 그러면 지문 → 거절이 반복됨)
  static void _hook() {
    if (_hooked) return;
    _hooked = true;
    onAdminCookieRejected = () => forget().ignore();
  }

  // 이 폰에 지문이 등록돼 있어 쓸 수 있는지
  static Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (e) {
      debugPrint('지문 인증 확인 실패: $e');
      return false;
    }
  }

  // 지문으로 저장해 둔 관리자 쿠키를 꺼내 씀. 저장된 게 없거나 인증 실패 · 취소면 false
  static Future<bool> unlock() async {
    _hook();
    try {
      final saved = await _storage.read(key: _key);
      if (saved == null || _expired(saved)) {
        if (saved != null) await forget();
        return false;
      }
      final ok = await _auth.authenticate(
        localizedReason: '관리자 로그인',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      if (!ok) return false;
      restoreAdminCookie(saved);
      return true;
    } catch (e) {
      debugPrint('지문 로그인 실패: $e');
      return false;
    }
  }

  // 비밀번호 로그인 직후 호출. 지문을 쓸 수 있으면 지금 쿠키를 저장하고 true
  static Future<bool> rememberCurrent() async {
    _hook();
    final cookie = adminCookie;
    if (cookie == null || !await available()) return false;
    try {
      await _storage.write(key: _key, value: cookie);
      return true;
    } catch (e) {
      debugPrint('관리자 쿠키 저장 실패: $e');
      return false;
    }
  }

  static Future<void> forget() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }

  // 쿠키 'lm_admin=<base64url(만료 epoch 초)>.<서명>' 의 만료 시각이 지났는지.
  // 형식이 다르면 판단하지 않고 서버에 맡김(false)
  static bool _expired(String cookie) {
    try {
      final value = cookie.substring(cookie.indexOf('=') + 1);
      final payload = value.substring(0, value.indexOf('.'));
      final secs = int.parse(
        String.fromCharCodes(
          base64Url.decode(base64Url.normalize(payload)),
        ),
      );
      return DateTime.now().millisecondsSinceEpoch ~/ 1000 >= secs;
    } catch (_) {
      return false;
    }
  }
}
