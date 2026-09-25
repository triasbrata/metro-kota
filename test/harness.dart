import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metro_kota/app.dart';
import 'package:metro_kota/city.dart';
import 'package:metro_kota/game.dart';

// Everything is drawn on the game canvas, so tests find things through the Ui of the last
// frame: hit areas by id (ui.rectOf) and the texts that were drawn (ui.texts).

const frame = Duration(milliseconds: 16);

Future<void> frames(WidgetTester tester, [int n = 5]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<App> boot(WidgetTester tester, Scene Function() home,
    {Size size = const Size(1280, 720), double dpr = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MetroKota(home: home));
  await tester.pump();
  await tester.pump(frame);
  return tester.state<App>(find.byType(MetroKota));
}

/// Opens [city] (optionally playing [game] instead of a fresh one) and returns its scene.
Future<CityScene> openCity(WidgetTester tester, City city, {Game? game}) async {
  final app = await boot(tester, () => CityScene(city));
  final st = app.top as CityScene;
  if (game != null) st.game = game;
  await tester.pump(frame);
  await tester.pump(frame);
  return st;
}

extension Find on App {
  Offset at(String id) {
    final r = ui.rectOf(id);
    if (r == null) throw StateError('no "$id" on screen');
    return r.center;
  }

  bool has(String id) => ui.rectOf(id) != null;
  bool shows(String s) => ui.texts.any((t) => t.contains(s));
}

extension Screen on CityScene {
  Offset screen(Offset world) => origin + world * scale;
}

Future<void> tapId(WidgetTester tester, App app, String id) async {
  await tester.tapAt(app.at(id));
  await tester.pump(frame);
  await tester.pump(frame);
}
