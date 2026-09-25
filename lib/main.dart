import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'game.dart';
import 'menu.dart';
import 'settings.dart';
import 'sfx.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Settings.load(); // before the music starts, so it respects the player's choice
  Sounds.init();
  SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  // Everything the player sees is drawn by the game engine (see app.dart).
  runApp(MetroKota(home: WelcomeScene.new));
}

const _progressKey = 'citiesCleared';

/// Cities are played in order; a cleared city stays open to play again.
Future<void> markCleared(City city) async {
  final prefs = await SharedPreferences.getInstance();
  final n = cities.indexOf(city) + 1;
  if (n > (prefs.getInt(_progressKey) ?? 0)) await prefs.setInt(_progressKey, n);
}

/// The score of each city's last finished run: until game over or until the player left
/// the cleared city (on to the next one, or out of endless mode).
Future<void> recordRun(Game g) async {
  try {
    await (await SharedPreferences.getInstance()).setInt('lastScore:${g.city.name}', g.score);
  } catch (_) {}
}

Future<Map<String, int>> lastScores() async {
  try {
    final p = await SharedPreferences.getInstance();
    return {
      for (final c in cities)
        c.name: ?p.getInt('lastScore:${c.name}'),
    };
  } catch (_) {
    return {};
  }
}

/// How many cities are cleared (the next one to play is cities[that]).
Future<int> clearedCount() async {
  try {
    return (await SharedPreferences.getInstance()).getInt(_progressKey) ?? 0;
  } catch (_) {
    return 0;
  }
}

/// Back to the first city: cleared cities and any city in progress are forgotten.
Future<void> resetProgress() async {
  await (await SharedPreferences.getInstance()).remove(_progressKey);
  await clearSavedGame();
}
