import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game.dart';
import 'sfx.dart';

/// Player settings, kept on the device.
class Settings {
  static bool music = true, sfx = true;
  static double musicVolume = .35, sfxVolume = 1;
  static bool showFps = !kReleaseMode;

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      music = p.getBool('music') ?? music;
      sfx = p.getBool('sfx') ?? sfx;
      musicVolume = p.getDouble('musicVolume') ?? musicVolume;
      sfxVolume = p.getDouble('sfxVolume') ?? sfxVolume;
      showFps = p.getBool('showFps') ?? showFps;
    } catch (e) {
      debugPrint('Settings not loaded: $e');
    }
    apply();
  }

  /// Applies the current values and stores them.
  static Future<void> save() async {
    apply();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('music', music);
      await p.setBool('sfx', sfx);
      await p.setDouble('musicVolume', musicVolume);
      await p.setDouble('sfxVolume', sfxVolume);
      await p.setBool('showFps', showFps);
    } catch (e) {
      debugPrint('Settings not saved: $e');
    }
  }

  /// Applies the current values without storing them (e.g. while a volume slider is dragged).
  static void apply() =>Sounds.configure(sfx: sfx, sfxVol: sfxVolume, music: music, musicVol: musicVolume);
}

// ---- the city in progress, so it can be resumed ----

const _saveKey = 'savedGame';

/// Stores [g] to resume later; a finished city (won or lost) removes the save instead.
/// A won city played on endless is saved like any other.
Future<void> saveGame(Game g) async {
  try {
    final p = await SharedPreferences.getInstance();
    if (g.gameOver != null || g.finished) {
      await p.remove(_saveKey);
    } else {
      await p.setString(_saveKey, jsonEncode({'city': g.city.name, 'game': g.toJson()}));
    }
  } catch (e) {
    debugPrint('Game not saved: $e');
  }
}

/// The city left in progress, if any (null when there is none or it can't be read).
Future<Game?> loadGame() async {
  try {
    final raw = (await SharedPreferences.getInstance()).getString(_saveKey);
    if (raw == null) return null;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final city = cities.where((c) => c.name == j['city']).firstOrNull;
    return city == null ? null : Game.fromJson(city, j['game'] as Map<String, dynamic>);
  } catch (e) {
    debugPrint('Saved game unreadable: $e');
    return null;
  }
}

Future<void> clearSavedGame() async {
  try {
    await (await SharedPreferences.getInstance()).remove(_saveKey);
  } catch (_) {}
}
