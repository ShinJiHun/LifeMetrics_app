import 'package:shared_preferences/shared_preferences.dart';

import '../models/persona.dart';

// 선택한 페르소나를 기기에 저장해 다음 실행 때 바로 해당 홈으로 진입
class PersonaStore {
  static const _key = 'selected_persona';

  static Future<Persona?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_key);
    return Persona.values.where((p) => p.name == name).firstOrNull;
  }

  static Future<void> save(Persona persona) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, persona.name);
  }
}
