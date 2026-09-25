import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metro_kota/game.dart';

import 'harness.dart';

const city = City('Uji', '', []);

void main() {
  testWidgets('while planning, holding on a planned station takes it out of the plan', (tester) async {
    final g = Game(city, spawn: false);
    final st = await openCity(tester, city, game: g);
    final a = g.addStation(const Offset(100, 100), Shape.circle);
    final b = g.addStation(const Offset(250, 100), Shape.triangle);
    final c = g.addStation(const Offset(400, 100), Shape.square);
    final d = g.addStation(const Offset(400, 300), Shape.star);
    await tester.pump();
    Offset screen(Offset w) => st.screen(w);

    final gst = await tester.startGesture(screen(a.pos));
    var at = a.pos;
    for (final to in [b.pos, c.pos, d.pos, b.pos]) {
      for (var i = 1; i <= 10; i++) {
        await gst.moveTo(screen(Offset.lerp(at, to, i / 10)!));
        await tester.pump(frame);
      }
      at = to;
    }
    expect(st.planned, [b, c, d], reason: 'back on b, which is not the previous stop');
    await tester.pump(const Duration(milliseconds: 1200));
    expect(st.planned, [c, d], reason: 'held on b: dropped from the plan');
    await tester.pump(const Duration(milliseconds: 100));
    expect(st.planned, [c, d], reason: 'not re-added while the finger stays on it');
    await gst.up();
    expect(g.lines.single.stops, [a, c, d]);

    // Pausing on the newest planned station before letting go keeps it.
    final e = g.addStation(const Offset(600, 300), Shape.diamond);
    final ext = await tester.startGesture(screen(d.pos));
    for (var i = 1; i <= 10; i++) {
      await ext.moveTo(screen(Offset.lerp(d.pos, e.pos, i / 10)!));
      await tester.pump(frame);
    }
    await tester.pump(const Duration(milliseconds: 1500));
    await ext.up();
    expect(g.lines.single.stops, [a, c, d, e]);
  });

  testWidgets('FPS meter shows the frame rate and F toggles it', (tester) async {
    final app = (await openCity(tester, city)).app;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(microseconds: 16667));
    }
    expect(app.shows('60 fps'), isTrue, reason: 'on by default in debug/test builds');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump(frame);
    expect(app.shows('fps'), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump(frame);
    expect(app.shows('fps'), isTrue);
  });

  testWidgets('grab track, hold it on its station for a second, release: station detached', (tester) async {
    final g = Game(city, spawn: false);
    final st = await openCity(tester, city, game: g);
    final a = g.addStation(const Offset(200, 300), Shape.circle);
    final b = g.addStation(const Offset(400, 300), Shape.triangle);
    final c = g.addStation(const Offset(600, 300), Shape.square);
    final l = g.createLine(a, b)!;
    g.extend(l, c, atHead: false);
    await tester.pump();
    Offset screen(Offset w) => st.screen(w);

    Future<void> grabAndHold(Duration hold) async {
      final from = screen(const Offset(500, 300)); // on the b–c track
      final gst = await tester.startGesture(from);
      for (var i = 1; i <= 10; i++) {
        await gst.moveTo(Offset.lerp(from, screen(b.pos), i / 10)!);
        await tester.pump(frame);
      }
      await tester.pump(hold);
      await gst.up();
      await tester.pump();
    }

    await grabAndHold(const Duration(milliseconds: 400));
    expect(l.stops, [a, b, c], reason: 'too short a hold: nothing happens');
    await grabAndHold(const Duration(milliseconds: 1200));
    expect(l.stops, [a, c], reason: 'b detached, a and c joined');

    // Line's end: from end station d go out of it, come back in and stay → d is detached.
    final d = g.addStation(const Offset(800, 300), Shape.star);
    g.extend(l, d, atHead: false); // a – c – d
    await tester.pump();
    final gst = await tester.startGesture(screen(d.pos));
    final inside = screen(d.pos), outside = screen(d.pos + const Offset(0, 80));
    for (final (from, to) in [(inside, outside), (outside, inside)]) {
      for (var i = 1; i <= 10; i++) {
        await gst.moveTo(Offset.lerp(from, to, i / 10)!);
        await tester.pump(frame);
      }
    }
    await tester.pump(const Duration(milliseconds: 700));
    await gst.up();
    expect(l.stops, [a, c], reason: 'end station d detached');
  });

  testWidgets('dragging only plans; track is built on release, and only if affordable', (tester) async {
    final g = Game(city, spawn: false);
    final st = await openCity(tester, city, game: g);
    final a = g.addStation(const Offset(100, 100), Shape.circle);
    final b = g.addStation(const Offset(250, 100), Shape.triangle);
    final c = g.addStation(const Offset(400, 100), Shape.square);
    await tester.pump();
    Offset screen(Offset w) => st.screen(w);

    Future<void> moveThrough(TestGesture gst, List<Offset> world) async {
      var at = world.first;
      for (final to in world.skip(1)) {
        for (var i = 1; i <= 10; i++) {
          await gst.moveTo(screen(Offset.lerp(at, to, i / 10)!));
          await tester.pump(frame);
        }
        at = to;
      }
    }

    // a -> b -> c (in, in), back into b and stay (in again + dwell drops b), release: a–c built.
    final money = g.money;
    final gst = await tester.startGesture(screen(a.pos));
    await moveThrough(gst, [a.pos, b.pos, c.pos]); // quick swipe: big steps past the touch slop
    expect(g.lines, isEmpty, reason: 'still planning');
    expect(g.money, money, reason: 'nothing paid while planning');
    expect(st.planned, [b, c]);
    await moveThrough(gst, [c.pos, b.pos]);
    expect(st.planned, [b, c], reason: 'just re-entering does nothing yet');
    await tester.pump(const Duration(milliseconds: 600));
    expect(st.planned, [c], reason: 'stayed in b: dropped from the plan');
    await moveThrough(gst, [b.pos, c.pos]);
    await gst.up();
    expect(g.lines.single.stops, [a, c]);
    expect(g.money, money - Game.segmentCost);

    // Extending c -> b costs more than we have: nothing is built.
    g.money = Game.segmentCost - 1;
    final ext = await tester.startGesture(screen(c.pos));
    await moveThrough(ext, [c.pos, b.pos]);
    await ext.up();
    expect(g.lines.single.stops, [a, c]);
    expect(g.money, Game.segmentCost - 1);
  });

  testWidgets('goals and fare stay compact until tapped', (tester) async {
    final app = (await openCity(tester, city)).app;
    expect(app.has('statsPanel'), isFalse);
    expect(app.has('fare-'), isFalse);
    await tapId(tester, app, 'stats');
    await tapId(tester, app, 'fare');
    expect(app.has('statsPanel'), isTrue);
    expect(app.has('fare-'), isTrue);
  });

  testWidgets('Space pauses, and resumes at the previous speed', (tester) async {
    final st = await openCity(tester, city);
    await tapId(tester, st.app, 'speed2');
    expect(st.speed, 2, reason: 'fast forward is 2×, not 3×');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(st.speed, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(st.speed, 2);
  });

  testWidgets('desktop: wheel zooms at the cursor, right-drag pans without drawing track', (tester) async {
    final g = Game(city, spawn: false);
    final st = await openCity(tester, city, game: g);
    final a = g.addStation(const Offset(480, 300), Shape.circle);
    final b = g.addStation(const Offset(700, 300), Shape.triangle);
    await tester.pump();
    Offset screen(Offset w) => st.screen(w);

    final cursor = screen(a.pos);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(cursor));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -300)));
    await tester.pump(frame);
    expect(st.zoom, greaterThan(1.5));
    expect((screen(a.pos) - cursor).distance, lessThan(1), reason: 'zooms around the cursor');

    final camBefore = st.cam;
    final right = await tester.startGesture(screen(a.pos), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    for (var i = 1; i <= 10; i++) {
      await right.moveBy(const Offset(-20, 0));
      await tester.pump(frame);
    }
    await right.up();
    await tester.pump(frame);
    expect(st.cam.dx, lessThan(camBefore.dx), reason: 'map panned');
    expect(g.lines, isEmpty, reason: 'right-drag never draws track');

    final left = await tester.startGesture(screen(a.pos), kind: PointerDeviceKind.mouse);
    for (var i = 1; i <= 10; i++) {
      await left.moveTo(Offset.lerp(screen(a.pos), screen(b.pos), i / 10)!);
      await tester.pump(frame);
    }
    await left.up();
    expect(g.lines.single.stops, [a, b]);
  });

  testWidgets('two-finger pinch zooms around the fingers; one finger still draws track', (tester) async {
    final g = Game(city, spawn: false);
    final st = await openCity(tester, city, game: g);
    final a = g.addStation(const Offset(480, 300), Shape.circle);
    final b = g.addStation(const Offset(560, 300), Shape.triangle);
    await tester.pump();
    Offset screen(Offset w) => st.screen(w);

    final centre = screen(const Offset(500, 310));
    final f1 = await tester.startGesture(centre - const Offset(40, 0), pointer: 1);
    final f2 = await tester.startGesture(centre + const Offset(40, 0), pointer: 2);
    for (var i = 1; i <= 10; i++) {
      await f1.moveTo(centre - Offset(40.0 + i * 8, 0));
      await f2.moveTo(centre + Offset(40.0 + i * 8, 0));
      await tester.pump(frame);
    }
    await f1.up();
    await f2.up();
    await tester.pump(frame);
    expect(st.zoom, greaterThan(1.5));
    expect(g.lines, isEmpty, reason: 'pinching never draws track');
    final w = (screen(const Offset(500, 310)) - centre).distance;
    expect(w, lessThan(15), reason: 'the point between the fingers stays put');

    final d = await tester.startGesture(screen(a.pos));
    for (var i = 1; i <= 10; i++) {
      await d.moveTo(Offset.lerp(screen(a.pos), screen(b.pos), i / 10)!);
      await tester.pump(frame);
    }
    await d.up();
    expect(g.lines.single.stops, [a, b]);

    await tester.pump(frame);
    await tapId(tester, st.app, 'fit');
    expect(st.zoom, 1);
  });

  testWidgets('event pop-up pauses the game until Oke', (tester) async {
    final g = Game(city, spawn: false);
    final st = await openCity(tester, city, game: g);
    final app = st.app;
    g.popups.add(('🚨', 'Kecelakaan kereta!', 'Bayar ganti rugi.'));
    await tester.pump(frame);
    await tester.pump(frame);
    await tester.pump(const Duration(milliseconds: 300));
    expect(app.shows('Kecelakaan kereta!'), isTrue);
    expect(st.speed, 0);
    final t = g.time;
    await tester.pump(const Duration(seconds: 1));
    expect(g.time, t, reason: 'paused while the pop-up is open');

    await tapId(tester, app, 'oke');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(app.shows('Kecelakaan kereta!'), isFalse);
    expect(st.speed, 1);
  });

  testWidgets('drag opens a line, drag on the track inserts, drag from the cap extends', (tester) async {
    final g = Game(city, spawn: false);
    final st = await openCity(tester, city, game: g);
    final a = g.addStation(const Offset(100, 100), Shape.circle);
    final b = g.addStation(const Offset(250, 100), Shape.triangle);
    final c = g.addStation(const Offset(175, 230), Shape.square);
    final d = g.addStation(const Offset(150, 420), Shape.star);
    await tester.pump();
    Offset screen(Offset w) => st.screen(w);

    Future<void> drag(Offset from, Offset to) async {
      final gesture = await tester.startGesture(screen(from));
      for (var i = 1; i <= 20; i++) {
        await gesture.moveTo(screen(Offset.lerp(from, to, i / 20)!));
        await tester.pump(frame);
      }
      await gesture.up();
    }

    await drag(a.pos, b.pos);
    final l = g.lines.single;
    expect(l.stops, [a, b]);

    await drag(const Offset(175, 100), c.pos); // grab the middle of the track
    expect(l.stops, [a, c, b]);

    final tip = g.capTip(l, head: false);
    await drag(tip + (tip - b.pos) * .5, d.pos); // finger just past the "T"
    expect(l.stops, [a, c, b, d]);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('drag a train onto the track; sliding along it sets the direction', (tester) async {
    final g = Game(city, spawn: false);
    final st = await openCity(tester, city, game: g);
    final a = g.addStation(const Offset(100, 100), Shape.circle);
    final b = g.addStation(const Offset(500, 100), Shape.triangle);
    final l = g.createLine(a, b)!;
    await frames(tester, 3);
    Offset screen(Offset w) => st.screen(w);

    Future<Train> dropTrain(double slide) async {
      final from = st.app.at('trainToken');
      final gst = await tester.startGesture(from);
      final over = screen(const Offset(300, 100));
      for (var i = 1; i <= 10; i++) {
        await gst.moveTo(Offset.lerp(from, over, i / 10)!);
        await tester.pump(frame);
      }
      for (var i = 1; i <= 5; i++) {
        await gst.moveTo(over + Offset(slide * i, 0));
        await tester.pump(frame);
      }
      expect(st.trainSpot, isNotNull, reason: 'snapped to the track');
      await gst.up();
      await tester.pump(frame);
      return l.trains.last;
    }

    final left = await dropTrain(-6);
    expect(l.trains, hasLength(2));
    expect(left.to, a, reason: 'slid towards a');
    final right = await dropTrain(6);
    expect(l.trains, hasLength(3));
    expect(right.to, b, reason: 'slid towards b');
    expect(g.money, city.startMoney - Game.segmentCost - 2 * Game.trainCost);
  });

  testWidgets('lift a train off the track and slide it the other way: it turns round, for free',
      (tester) async {
    final g = Game(city, spawn: false);
    final st = await openCity(tester, city, game: g);
    final a = g.addStation(const Offset(100, 100), Shape.circle);
    final b = g.addStation(const Offset(500, 100), Shape.triangle);
    final l = g.createLine(a, b)!;
    l.trains.clear();
    expect(g.addTrain(l, seg: 0, dir: 1, at: 250), isTrue);
    st.speed = 0.0; // keep it where we grab it
    await frames(tester, 3);
    final money = g.money;
    Offset screen(Offset w) => st.screen(w);

    final gst = await tester.startGesture(screen(const Offset(350, 100))); // 250 px from a
    for (var i = 1; i <= 8; i++) {
      await gst.moveTo(screen(Offset(350 - 6.0 * i, 100)));
      await tester.pump(frame);
    }
    expect(l.trains.single.held, isTrue, reason: 'picked up (not drawn on the track while held)');
    await gst.up();
    await tester.pump(frame);
    final t = l.trains.single;
    expect(t.held, isFalse);
    expect(t.to, a, reason: 'slid towards a: now runs b → a');
    expect(g.money, money);
    expect(l.stops, [a, b], reason: 'the track itself was not dragged');
  });

  testWidgets('train/carriage buttons are off while unaffordable; a carriage is dragged onto a train',
      (tester) async {
    final g = Game(city, spawn: false);
    final st = await openCity(tester, city, game: g);
    final app = st.app;
    final a = g.addStation(const Offset(100, 100), Shape.circle);
    final b = g.addStation(const Offset(500, 100), Shape.triangle);
    final l = g.createLine(a, b)!;
    final t = l.trains.single;
    Offset screen(Offset w) => st.screen(w);
    Future<void> drag(String token, Offset world) async {
      final from = app.at(token);
      final gst = await tester.startGesture(from);
      for (var i = 1; i <= 10; i++) {
        await gst.moveTo(Offset.lerp(from, screen(world), i / 10)!);
        await tester.pump(frame);
      }
      await gst.up();
      await tester.pump(frame);
    }

    bool on(String token) => app.ui.hit(app.at(token))?.onPanStart != null;

    g.money = Game.carCost; // enough for a carriage, not for a train
    await frames(tester, 3);
    expect(on('trainToken'), isFalse);
    expect(on('carToken'), isTrue);
    await drag('trainToken', const Offset(300, 100));
    expect(l.trains, hasLength(1), reason: 'disabled: dragging does nothing');

    final trainAt = pointAlong(pathBetween(t.from.pos, t.to.pos), t.along).$1;
    st.speed = 0.0; // keep the train still while we aim at it
    await drag('carToken', trainAt);
    expect(t.cars, 1);
    expect(g.money, 0);
    await frames(tester, 3);
    expect(on('carToken'), isFalse, reason: 'out of money now');

    g.money = Game.trainCost; // exactly enough: back on
    await frames(tester, 3);
    expect(on('trainToken'), isTrue);
  });

  testWidgets('grab a track, pull it onto open ground, release: the track takes that shape', (tester) async {
    final g = Game(city, spawn: false);
    final st = await openCity(tester, city, game: g);
    final a = g.addStation(const Offset(100, 100), Shape.circle);
    final b = g.addStation(const Offset(500, 100), Shape.triangle);
    final l = g.createLine(a, b)!;
    await tester.pump();
    Offset screen(Offset w) => st.screen(w);

    final money = g.money;
    final gst = await tester.startGesture(screen(const Offset(300, 100)));
    for (var i = 1; i <= 10; i++) {
      await gst.moveTo(screen(Offset.lerp(const Offset(300, 100), const Offset(300, 300), i / 10)!));
      await tester.pump(frame);
    }
    expect(l.bends, isEmpty, reason: 'only planning while dragging');
    await gst.up();
    final via = l.bends[MetroLine.key(a, b)]!;
    expect((via - const Offset(300, 300)).distance, lessThan(1));
    expect(g.money, money - Game.segmentCost);
  });

  testWidgets('drag a -> b -> c and release back on a: a loop line', (tester) async {
    final g = Game(city, spawn: false);
    final st = await openCity(tester, city, game: g);
    final a = g.addStation(const Offset(100, 100), Shape.circle);
    final b = g.addStation(const Offset(300, 100), Shape.triangle);
    final c = g.addStation(const Offset(200, 250), Shape.square);
    await tester.pump();
    Offset screen(Offset w) => st.screen(w);

    final gst = await tester.startGesture(screen(a.pos));
    var at = a.pos;
    for (final to in [b.pos, c.pos, a.pos]) {
      for (var i = 1; i <= 10; i++) {
        await gst.moveTo(screen(Offset.lerp(at, to, i / 10)!));
        await tester.pump(frame);
      }
      at = to;
    }
    await gst.up();
    final l = g.lines.single;
    expect(l.loop, isTrue);
    expect(l.stops, [a, b, c, a]);
    expect(g.money, city.startMoney - 3 * Game.segmentCost);
  });
}
