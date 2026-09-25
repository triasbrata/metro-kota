import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metro_kota/city.dart';
import 'package:metro_kota/game.dart';
import 'package:metro_kota/main.dart';
import 'package:metro_kota/menu.dart';
import 'package:metro_kota/settings.dart';
import 'package:metro_kota/ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

void main() {
  setUp(() {
    Settings.music = Settings.sfx = true;
    Settings.showFps = false;
  });

  testWidgets('welcome screen: no save = no Lanjutkan; a save = resume that very game', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var app = await boot(tester, WelcomeScene.new);
    await frames(tester, 2);
    expect(app.has('resume'), isFalse);
    expect(app.ui.texts, containsAll(['Main', 'Pengaturan']));

    final city = cities[1];
    final g = Game(city, seed: 1);
    g.createLine(g.stations[0], g.stations[1]);
    g.money = 12345;
    SharedPreferences.setMockInitialValues({
      'savedGame': jsonEncode({'city': city.name, 'game': g.toJson()}),
    });
    await tester.pumpWidget(const SizedBox());
    app = await boot(tester, WelcomeScene.new);
    await frames(tester, 2);
    expect(app.has('resume'), isTrue);
    expect(app.shows('${city.name} · Jan Tahun 1 · Rp12.345'), isTrue);
    expect(app.ui.texts, contains('Pilih kota'));

    await tapId(tester, app, 'resume');
    await frames(tester);
    final resumed = (app.top as CityScene).game;
    expect(resumed.city, city);
    expect(resumed.lines, hasLength(1));
    expect(resumed.stations, hasLength(g.stations.length));
  });

  testWidgets('a cleared city can be played again and shows its last earnings', (tester) async {
    final first = cities.first;
    SharedPreferences.setMockInitialValues({'citiesCleared': 1, 'lastScore:${first.name}': 54321});
    final app = await boot(tester, PickerScene.new);
    await frames(tester, 2);
    expect(app.ui.texts, contains(short(54321)));

    await tapId(tester, app, 'city:${first.name}');
    await frames(tester);
    final g = (app.top as CityScene).game;
    expect(g.city, first, reason: 'the cleared city opens again');

    // Game over records this run's score.
    g
      ..earned = 99900
      ..money = Game.debtLimit - 1
      ..time = Game.monthLength - 0.01; // the month ends on the next frame: bankrupt
    await frames(tester);
    expect(g.gameOver, isNotNull);
    await frames(tester);
    expect((await lastScores())[first.name], g.score);  });

  testWidgets('leaving a city saves it; the settings screen remembers its switches', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final st = await openCity(tester, cities.first);
    await frames(tester);
    st.game.money = 777;
    final app = st.app..replace(SettingsScene()); // the city scene exits
    await frames(tester, 2);
    final back = await loadGame();
    expect(back?.money, 777);

    await tapId(tester, app, 'musicSwitch');
    await frames(tester, 2);
    expect(Settings.music, isFalse);
    expect((await SharedPreferences.getInstance()).getBool('music'), isFalse);
  });

  testWidgets('"+" plans a new line by tapping: first station = start; tapping the start again = loop',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const city = City('Uji', '', []);
    final g = Game(city, spawn: false)..money = 100000;
    final st = await openCity(tester, city, game: g);
    final app = st.app;
    final a = g.addStation(const Offset(100, 100), Shape.circle);
    final b = g.addStation(const Offset(400, 100), Shape.triangle);
    final c = g.addStation(const Offset(250, 300), Shape.square);
    final d = g.addStation(const Offset(500, 300), Shape.star);
    final red = g.createLine(a, b)!; // a is an end of red: a plain drag from a would extend red
    await frames(tester);

    await tapId(tester, app, 'newLine');
    await frames(tester, 2);
    expect(app.shows('Ketuk stasiun awal jalur baru'), isTrue);
    for (final s in [a, c, d]) {
      await tester.tapAt(st.screen(s.pos));
      await frames(tester, 2);
    }
    expect(st.planned, [c, d]);
    await tester.tapAt(st.screen(c.pos)); // tapping a planned station drops it
    await frames(tester, 2);
    expect(st.planned, [d]);
    await tester.tapAt(st.screen(c.pos));
    await frames(tester, 2);
    await tapId(tester, app, 'buildPlan');
    await frames(tester, 2);
    expect(g.lines, hasLength(2));
    expect(g.lines.last.stops, [a, d, c], reason: 'a new line, not an extension of red');
    expect(red.stops, [a, b]);
    expect(st.newLineMode, isFalse);

    // Loop: + , b, c, d, then b again.
    await tapId(tester, app, 'newLine');
    await frames(tester, 2);
    for (final s in [b, c, d, b]) {
      await tester.tapAt(st.screen(s.pos));
      await frames(tester, 2);
    }
    expect(g.lines.last.loop, isTrue);
    expect(g.lines.last.stops, [b, c, d, b]);
  });
}
