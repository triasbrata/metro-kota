import 'dart:convert';
import 'dart:math' show min, pi, sqrt;

import 'package:flutter_test/flutter_test.dart';
import 'package:metro_kota/game.dart';

const plain = City('Uji', '', [
  Water(34, [Offset(300, 0), Offset(330, 200), Offset(520, 380), Offset(560, 620)]),
]);

void main() {
  test('every city starts with 3 stations on land', () {
    for (final c in cities) {
      final g = Game(c, seed: 1);
      expect(g.stations.length, 3, reason: c.name);
      expect(g.money, c.startMoney);
    }
  });

  test('a new city waits for its first track: no riders and no time passing until then', () {
    final g = Game(cities.first, seed: 1);
    for (var i = 0; i < 600; i++) {
      g.tick(0.1);
    }
    expect(g.time, 0);
    expect(g.stations.every((s) => s.waiting.isEmpty), isTrue);
    g.createLine(g.stations[0], g.stations[1]);
    g.tick(0.1);
    expect(g.time, greaterThan(0));
  });

  test('all three goals (money, stations connected, riders) clear the city and freeze it', () {
    const easy = City('Uji', '', [], goal: (money: 1000, stations: 3, riders: 2));
    final g = Game(easy, spawn: false);
    final a = g.addStation(const Offset(60, 100), Shape.circle);
    final b = g.addStation(const Offset(160, 100), Shape.triangle);
    final c = g.addStation(const Offset(260, 100), Shape.square);
    g
      ..earned = 1000
      ..delivered = 2;
    expect(g.won, isFalse, reason: 'no stations connected yet');
    final l = g.createLine(a, b)!;
    g.tick(0.01);
    expect(g.connectedStations, 2);
    expect(g.message, contains('tercapai'), reason: 'a reached goal is announced');
    expect(g.won, isFalse);
    g.extend(l, c, atHead: false);
    expect(g.won, isTrue);
    final t = g.time;
    g.tick(1);
    expect(g.time, t, reason: 'frozen once cleared');

    g.endless = true;
    expect(g.finished, isFalse);
    g.tick(1);
    expect(g.time, t + 1, reason: 'endless: the city keeps running');
    final back = Game.fromJson(easy, jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
    expect(back.endless, isTrue, reason: 'saved and resumed as endless');

    // ...and nothing ends it: not angry riders, not debt.
    g.anger = Game.angerLimit * 3;
    g.money = Game.debtLimit * 10;
    for (var i = 0; i < 3 * Game.monthLength; i++) {
      g.tick(1);
    }
    expect(g.gameOver, isNull);
  });

  test('no time limit: months passing never lose the city', () {
    final g = Game(plain, spawn: false);
    for (var i = 0; i < 40 * Game.monthLength; i++) {
      g.tick(1);
    }
    expect(g.month, 40);
    expect(g.gameOver, isNull);
  });

  test('stations with long waits stop spawning until a pickup resets them', () {
    final g = Game(plain, seed: 3, spawn: false);
    final a = g.addStation(const Offset(60, 100), Shape.circle);
    final b = g.addStation(const Offset(160, 100), Shape.triangle);
    a.waiting.addAll([Shape.triangle, Shape.triangle]);
    g.tick(Game.waitLimit + 1); // no line: nobody picks them up (one gives up)
    expect(a.wait, greaterThan(Game.waitLimit));
    for (var i = 0; i < 50; i++) {
      g.spawnPassenger();
    }
    expect(a.waiting.length, 1, reason: 'fed-up station spawns nobody');
    expect(b.waiting.length, 50);

    g.createLine(b, a); // train starts at b, reaches a and picks up
    for (var i = 0; i < 100 && a.wait > 0; i++) {
      g.tick(0.05);
    }
    expect(a.wait, 0);
    expect(a.spawnWeight, a.rep, reason: 'wait penalty gone; reputation still remembers the rider who left');
  });

  test('once the wait ring is full, riders leave one at a time', () {
    final g = Game(plain, spawn: false);
    final a = g.addStation(const Offset(60, 100), Shape.circle);
    g.addStation(const Offset(160, 100), Shape.triangle);
    a.waiting.addAll([Shape.triangle, Shape.square, Shape.triangle]);
    for (var t = 0.0; t < Game.waitLimit - 0.1; t += 0.1) {
      g.tick(0.1);
    }
    expect(a.waiting.length, 3, reason: 'nobody leaves before the ring is full');
    for (var t = 0.0; t < Game.giveUpEvery + 0.2; t += 0.1) {
      g.tick(0.1);
    }
    expect(a.waiting, [Shape.square, Shape.triangle], reason: 'longest-waiting leaves first');
    for (var t = 0.0; t < 2 * Game.giveUpEvery + 0.2; t += 0.1) {
      g.tick(0.1);
    }
    expect(a.waiting, isEmpty);
    expect(g.lost, 3);
    expect(a.wait, 0);
    expect(a.rep, closeTo(1 - 3 * Game.repLoss, 1e-9));
  });

  test('walk-outs are contagious within a station: each one makes the next come sooner, then it cools down', () {
    final g = Game(plain, spawn: false);
    final a = g.addStation(const Offset(60, 100), Shape.circle);
    final b = g.addStation(const Offset(160, 100), Shape.triangle);
    a.waiting.addAll(List.filled(8, Shape.triangle));
    a.wait = Game.waitLimit;
    final gaps = <double>[];
    var last = 0.0, t = 0.0;
    while (g.lost < 4) {
      final before = g.lost;
      g.tick(0.01);
      t += 0.01;
      if (g.lost > before) {
        gaps.add(t - last);
        last = t;
      }
    }
    expect(gaps[2], lessThan(gaps[1]));
    expect(gaps[3], lessThan(gaps[2]));
    // cooling only starts after the first walk-out (upset can't go below 0)
    expect(a.upset, closeTo(4 * Game.upsetPerLoss - (t - gaps[0]) * Game.upsetCooldown, 0.02));
    expect(b.upset, 0, reason: 'other stations are not affected');
    expect(b.giveUpInterval, Game.giveUpEvery);
    a.waiting.clear();
    g.tick(60);
    expect(a.upset, 0);
  });

  test('lines sharing a stretch of track get lanes side by side; the rest stays centred', () {
    final g = Game(plain, spawn: false)..money = 100000;
    final c = g.addStation(const Offset(100, 300), Shape.circle);
    final e = g.addStation(const Offset(250, 300), Shape.square); // west of the river
    final n = g.addStation(const Offset(300, 200), Shape.triangle);
    final a = g.createLine(c, e)!; // straight east along y=300
    final b = g.createLine(c, n)!; // east along y=300 to x=200, then diagonal up
    final lanes = laneLayout(g.lines, gap: 6);
    expect(lanes[(a, 0)], [(from: 0.0, to: 100.0, shift: const Offset(0, -3), shared: 2)]);
    expect(lanes[(b, 0)], [(from: 0.0, to: 100.0, shift: const Offset(0, 3), shared: 2)]);
    expect(laneAt(lanes[(a, 0)], 120), isNull, reason: 'past x=200 line a runs alone');
    // The drawn lane eases out around the end of the shared stretch (s = 100) and runs
    // straight on into the station at s = 0; linear between the knots 88 and 112.
    const len = 150.0;
    final za = lanes[(a, 0)]!;
    expect(laneShift(za, 0, len), const Offset(0, -3));
    expect(laneShift(za, 100 - laneEase, len), const Offset(0, -3));
    expect(laneShift(za, 100, len).dy, closeTo(-1.5, 1e-9));
    expect(laneShift(za, 100 + laneEase, len), Offset.zero);
    expect(laneShift(za, 94, len).dy, closeTo(-2.25, 1e-9), reason: 'straight between knots');
    expect(laneKnots(za, len).toSet(), {88.0, 112.0});
    // A third line elsewhere shares nothing.
    final l3 = g.createLine(g.addStation(const Offset(100, 500), Shape.star), g.addStation(const Offset(200, 560), Shape.diamond))!;
    expect(laneLayout(g.lines)[(l3, 0)], isNull);
  });

  test('freed land never gets another permit event, and zone names are never reused', () {
    final g = Game(plain, seed: 5, spawn: false)..money = 1 << 30;
    final first = g.spawnZone()!;
    g.buyZone(first);
    while (g.spawnZone() != null) {} // until the map has no room left
    expect(g.zones.length, greaterThan(3));
    expect(g.zones.map((z) => z.name).toSet(), hasLength(g.zones.length));
    for (final z in g.zones.skip(1)) {
      final touching = z.cells.any((c) => first.cells.contains(c) || hexNeighbors(c).any(first.cells.contains));
      expect(touching, isFalse, reason: '${z.name} must stay off the freed ${first.name}');
    }
    // Once every name has been used, no more permit events at all.
    final fresh = Game(plain, seed: 5, spawn: false);
    fresh.zones.addAll([for (final n in zoneNames) Zone(n, {(-50, -50)}, 1)..paid = true]);
    expect(fresh.spawnZone(), isNull);
  });

  test('carriages: 1/5 of a train, 6 more seats each, at most 3 per train', () {
    final g = Game(plain, spawn: false)..money = 100000;
    final a = g.addStation(const Offset(60, 100), Shape.circle);
    final b = g.addStation(const Offset(260, 100), Shape.triangle);
    final t = g.createLine(a, b)!.trains.single;
    expect(Game.carCost, Game.trainCost ~/ 5);
    final before = g.money;
    expect(g.addCar(t), isTrue);
    expect(g.money, before - Game.carCost);
    expect(t.capacity, 2 * Game.trainCapacity);
    expect(g.trainAt(a.pos), t, reason: 'a fresh train sits at its first stop');
    g.addCar(t);
    g.addCar(t);
    expect(g.addCar(t), isFalse, reason: 'max ${Game.maxCars}');
    expect(t.capacity, 4 * Game.trainCapacity);
    // All 20 waiting riders fit on board at once.
    a.waiting.addAll(List.filled(20, Shape.triangle));
    for (var i = 0; i < 200 && a.waiting.isNotEmpty; i++) {
      g.tick(0.05);
    }
    expect(a.waiting, isEmpty);
    expect(t.riders, hasLength(20));
    g.money = Game.carCost - 1;
    final t2 = g.lines.single.trains.single;
    t2.cars = 0;
    expect(g.addCar(t2), isFalse, reason: 'not enough money');
  });

  test('carriages always ride on the track: through bends, stations, a terminus and a loop', () {
    final g = Game(plain, spawn: false)..money = 1 << 30;
    final a = g.addStation(const Offset(60, 100), Shape.circle);
    final b = g.addStation(const Offset(200, 160), Shape.triangle);
    final c = g.addStation(const Offset(120, 300), Shape.square);
    final open = g.createLine(a, b)!..trains.clear();
    g.extend(open, c, atHead: false);
    g.reshape(open, 1, const Offset(260, 260)); // a bent segment too
    final ring = g.createLine(g.addStation(const Offset(60, 450), Shape.star), g.addStation(const Offset(220, 420), Shape.diamond))!
      ..trains.clear();
    g.extend(ring, g.addStation(const Offset(150, 580), Shape.circle), atHead: false);
    g.closeLoop(ring);
    for (final l in [open, ring]) {
      g.addTrain(l);
      l.trains.single.cars = Game.maxCars;
    }
    double offTrack(Offset p) => [
          for (final l in g.lines)
            for (var i = 0; i + 1 < l.stops.length; i++) distToPolyline(p, l.route(l.stops[i], l.stops[i + 1])),
        ].reduce(min);
    for (var step = 0; step < 1200; step++) {
      g.tick(0.05);
      for (final l in g.lines) {
        final t = l.trains.single;
        for (var k = 0; k <= t.cars; k++) {
          final pose = trackBehind(t, k * 31.0);
          expect(offTrack(pose.pos), lessThan(0.5), reason: 'car $k of the ${l == ring ? 'loop' : 'open'} line, step $step');
        }
      }
    }
  });

  test('a bend point near the straight line does not fold the track', () {
    // The screenshot case: two stations almost one above the other, bent a little aside.
    const a = Offset(783, 250), b = Offset(800, 530), via = Offset(805, 390);
    final r = trackRoute(a, b, via);
    expect(distToPolyline(via, r), lessThan(1e-6), reason: 'still through the bend point');
    for (var i = 0; i + 2 < r.length; i++) {
      final u = r[i + 1] - r[i], v = r[i + 2] - r[i + 1];
      if (u.distance < 1e-6 || v.distance < 1e-6) continue;
      final turn = ((v.direction - u.direction).abs() % (2 * pi));
      expect(min(turn, 2 * pi - turn), lessThanOrEqualTo(pi / 4 + 1e-9), reason: 'no sharp fold at corner ${r[i + 1]}');
    }
    // Leans aside once and back once (≤ 90° in all), instead of straight-jog-straight.
    var turning = 0.0;
    for (var i = 0; i + 2 < r.length; i++) {
      final u = r[i + 1] - r[i], v = r[i + 2] - r[i + 1];
      if (u.distance < 1e-6 || v.distance < 1e-6) continue;
      final d = (v.direction - u.direction).abs() % (2 * pi);
      turning += min(d, 2 * pi - d);
    }
    expect(turning, lessThanOrEqualTo(pi / 2 + 1e-9));
    expect(trackRoute(b, a, via), r.reversed.toList());
  });

  test('reshaping bends a segment through a point, like the plan showed', () {
    final g = Game(plain, spawn: false)..money = 100000;
    final a = g.addStation(const Offset(60, 100), Shape.circle);
    final b = g.addStation(const Offset(260, 100), Shape.triangle);
    final l = g.createLine(a, b)!;
    const via = Offset(160, 200);
    final before = g.money;
    expect(g.reshape(l, 0, via), isTrue);
    expect(g.money, before - Game.segmentCost);
    expect(distToPolyline(via, l.route(a, b)), lessThan(1e-6));
    expect(l.route(a, b), trackRoute(a.pos, b.pos, via), reason: 'the same path as the plan preview a -> finger -> b');
    expect(l.route(b, a), l.route(a, b).reversed.toList());
    expect(g.segmentAt(via), (l, 0), reason: 'the bent track can be grabbed where it now runs');
    // Trains follow the bent track.
    for (var i = 0; i < 40; i++) {
      g.tick(0.05);
      expect(distToPolyline(trackBehind(l.trains.single, 0).pos, l.route(a, b)), lessThan(0.5));
    }
    // Straighten again.
    expect(g.reshape(l, 0, null), isTrue);
    expect(l.bends, isEmpty);
    expect(l.route(a, b), pathBetween(a.pos, b.pos));
  });

  test('reshaping bridged track keeps a nearby bridge, pays for one far away', () {
    final g = Game(plain, spawn: false)..money = 100000;
    final a = g.addStation(const Offset(200, 330), Shape.circle);
    final b = g.addStation(const Offset(700, 330), Shape.triangle);
    final l = g.createLine(a, b)!;
    g.tick(20);
    var before = g.money;
    g.reshape(l, 0, const Offset(450, 380)); // crosses a little downstream of the old bridge
    expect(g.money, before - Game.segmentCost);
    expect(l.building, isEmpty);
    before = g.money;
    g.reshape(l, 0, const Offset(360, 60)); // way upstream: a new bridge
    expect(g.money, before - Game.segmentCost - plain.bridgeCost);
    expect(l.building, hasLength(1));
  });

  test('save and resume: a city in full swing comes back exactly as it was, and keeps going', () {
    final g = Game(plain, seed: 3)..money = 1 << 20;
    for (var i = 0; i < 6; i++) {
      g.spawnStation();
    }
    final s = g.stations;
    final red = g.createLine(s[0], s[1])!;
    g.extend(red, s[2], atHead: false);
    g.closeLoop(red);
    g.reshape(red, 0, s[0].pos + const Offset(40, 60));
    final blue = g.createLine(s[3], s[4])!;
    g.addTrain(blue);
    blue.trains.first.cars = 2;
    g.spawnZone();
    g.buyZone(g.zones.first);
    g.spawnZone();
    g.startFestival();
    for (var i = 0; i < 400; i++) {
      g.tick(0.05);
    }
    g.accident(blue.trains.first);
    g.fare = 450;

    final saved = jsonEncode(g.toJson());
    final back = Game.fromJson(plain, jsonDecode(saved) as Map<String, dynamic>);
    expect(jsonEncode(back.toJson()), saved);
    final t = back.stations;
    expect(back.lines[0].route(t[0], t[1]), g.lines[0].route(s[0], s[1]), reason: 'bend kept');
    expect(back.lines[1].trains.first.cars, 2);
    expect(back.festivalAt?.id, g.festivalAt?.id);

    // The resumed city carries on: trains move, new stations still appear. (Endless, so the
    // riders this neglected city loses can't end it first.)
    back.endless = true;
    final stations = back.stations.length;
    for (var i = 0; i < 1200 && back.gameOver == null; i++) {
      back.tick(0.05);
    }
    expect(back.stations.length, greaterThan(stations));
    expect(back.time, greaterThan(g.time));
  });

  test('a carriage dropped on a track goes to the train with the fewest carriages', () {
    final g = Game(plain, spawn: false)..money = 100000;
    final a = g.addStation(const Offset(60, 100), Shape.circle);
    final b = g.addStation(const Offset(260, 100), Shape.triangle);
    final l = g.createLine(a, b)!;
    final first = l.trains.single..cars = 1;
    expect(g.addTrain(l, seg: 0, at: 150), isTrue);
    final second = l.trains.last;
    expect(g.trainForCar(l, a.pos), second, reason: 'fewest carriages wins over nearest');
    second.cars = 1;
    expect(g.trainForCar(l, a.pos), first, reason: 'tie: the nearest');
    first.cars = second.cars = Game.maxCars;
    expect(g.trainForCar(l, a.pos), isNull, reason: 'all full');
  });

  test('trains keep a gap: too close is refused with a message; a lifted train can be turned round', () {
    final g = Game(plain, spawn: false);
    final a = g.addStation(const Offset(60, 100), Shape.circle);
    final b = g.addStation(const Offset(260, 100), Shape.triangle); // clear of the river
    final l = g.createLine(a, b)!;
    l.trains.clear();
    expect(g.addTrain(l, seg: 0, at: 60), isTrue);
    final money = g.money;
    expect(g.addTrain(l, seg: 0, at: 80), isFalse);
    expect(g.message, contains('terlalu dekat'));
    expect(g.money, money, reason: 'not charged');
    expect(g.fitsTrain(l, 0, 1, 160), isTrue);

    final t = l.trains.single..cars = 1;
    t.riders.add(Shape.square);
    final moved = g.moveTrain(t, l, seg: 0, dir: -1, at: 60)!;
    expect(l.trains, [moved], reason: 'moving ignores its own old spot');
    expect((moved.from, moved.to), (b, a));
    expect(moved.cars, 1);
    expect(moved.riders, [Shape.square]);
    expect(g.money, money, reason: 'moving is free');

    moved.broken = 3;
    expect(g.moveTrain(moved, l, seg: 0, dir: 1, at: 160), isNull, reason: 'stuck in an accident');
  });

  test('a new train can go anywhere on a track, running either way', () {
    final g = Game(plain, spawn: false);
    final a = g.addStation(const Offset(60, 100), Shape.circle);
    final b = g.addStation(const Offset(260, 100), Shape.triangle);
    final l = g.createLine(a, b)!;
    final before = g.money;
    expect(g.addTrain(l, seg: 0, dir: -1, at: 150), isTrue);
    expect(g.money, before - Game.trainCost);
    final t = l.trains.last;
    expect((t.from, t.to), (b, a));
    expect(t.along, closeTo(50, 1e-9), reason: '150 from a = 50 from b');
    g.tick(0.1);
    expect(pointAlong(pathBetween(t.from.pos, t.to.pos), t.along).$1.dx, lessThan(210), reason: 'heading to a');
  });

  test('loop: closing a 3-station line makes trains go round, never back', () {
    final g = Game(plain, spawn: false);
    final a = g.addStation(const Offset(60, 100), Shape.circle);
    final b = g.addStation(const Offset(200, 100), Shape.triangle);
    final c = g.addStation(const Offset(130, 220), Shape.square);
    final l = g.createLine(a, b)!;
    expect(g.closeLoop(l), isFalse, reason: 'needs 3 stations');
    g.extend(l, c, atHead: false);
    final before = g.money;
    expect(g.closeLoop(l), isTrue);
    expect(g.money, before - Game.segmentCost);
    expect(l.stops, [a, b, c, a]);
    expect(g.extend(l, g.addStation(const Offset(260, 250), Shape.star), atHead: false), isFalse);
    expect(g.capAt(g.capTip(l, head: true)), isNull, reason: 'a loop has no end caps');
    final t = l.trains.single;
    final seen = <Station>[];
    for (var i = 0; i < 600; i++) {
      g.tick(0.05);
      expect(t.dir, 1);
      if (t.along == 0 && (seen.isEmpty || seen.last != t.from)) seen.add(t.from);
    }
    expect(seen.take(5), [b, c, a, b, c]);
    // A rider rides the loop the short way round: c -> a directly, not back via b.
    c.waiting.add(Shape.circle);
    for (var i = 0; i < 600 && g.delivered == 0; i++) {
      g.tick(0.05);
    }
    expect(g.delivered, 1);
  });

  test('loop: detaching keeps the ring, even at its join station', () {
    final g = Game(plain, spawn: false);
    final a = g.addStation(const Offset(60, 100), Shape.circle);
    final b = g.addStation(const Offset(200, 100), Shape.triangle);
    final c = g.addStation(const Offset(200, 220), Shape.square);
    final d = g.addStation(const Offset(60, 220), Shape.star);
    final l = g.createLine(a, b)!;
    g.extend(l, c, atHead: false);
    g.extend(l, d, atHead: false);
    g.closeLoop(l);
    expect(g.detach(l, 0), isTrue);
    expect(l.stops, [b, c, d, b]);
    expect(l.loop, isTrue);
    expect(g.detach(l, 1), isFalse, reason: 'a loop keeps at least 3 stations');
    for (var i = 0; i < 400; i++) {
      g.tick(0.05);
      final t = l.trains.single;
      expect(t.seg, inInclusiveRange(0, l.stops.length - 2));
    }
  });

  test('reputation: losses speed up the ring and cut spawns, pickups raise spawns', () {
    final g = Game(plain, spawn: false);
    final a = g.addStation(const Offset(60, 100), Shape.circle);
    final b = g.addStation(const Offset(160, 100), Shape.triangle);
    a.rep = 0.5;
    a.waiting.add(Shape.triangle);
    g.tick(1);
    expect(a.wait, closeTo(2, 1e-9), reason: 'ring fills twice as fast');
    expect(a.spawnWeight, closeTo(0.5 * (1 - 2 / Game.waitLimit), 1e-9));

    g.createLine(b, a);
    for (var i = 0; i < 100 && a.waiting.isNotEmpty; i++) {
      g.tick(0.05);
    }
    expect(a.rep, closeTo(0.5 + Game.repGain, 1e-9));
    a.rep = 10;
    a.waiting.add(Shape.triangle);
    for (var i = 0; i < 100 && a.waiting.isNotEmpty; i++) {
      g.tick(0.05);
    }
    expect(a.rep, Game.repMax, reason: 'capped');
    expect(a.waitSpeed, 1, reason: 'good reputation never slows the ring below normal');
  });

  test('tunnels take time: trains turn back until construction is done', () {
    final g = Game(plain, spawn: false);
    final a = g.addStation(const Offset(60, 300), Shape.circle);
    final b = g.addStation(const Offset(200, 300), Shape.triangle);
    final c = g.addStation(const Offset(700, 300), Shape.square); // across the river
    final l = g.createLine(a, b)!;
    g.extend(l, c, atHead: false);
    expect(l.isBuilding(b, c), isTrue);
    expect(g.dist(Shape.square, a), greaterThan(100), reason: 'unfinished tunnel is not a route');

    final t = l.trains.single;
    var reachedC = false;
    for (var i = 0; i < (Game.tunnelBuildTime - 1) / 0.05; i++) {
      g.tick(0.05);
      reachedC |= t.from == c || t.to == c && t.along > 0;
    }
    expect(reachedC, isFalse);

    for (var i = 0; i < 400 && !(t.to == c && t.along > 0); i++) {
      g.tick(0.05);
    }
    expect(l.isBuilding(b, c), isFalse);
    expect(t.to, c, reason: 'train uses the tunnel once it is finished');
    expect(g.dist(Shape.square, a), 2);
  });

  test('permit zones block track until bought, and spawn clear of existing track', () {
    final g = Game(plain, seed: 2, spawn: false);
    final a = g.addStation(const Offset(60, 100), Shape.circle);
    final b = g.addStation(const Offset(260, 100), Shape.triangle);
    final z = Zone('Lahan Sengketa', {hexAt(const Offset(160, 100))}, 100); // one cell on the a–b track
    g.zones.add(z);

    expect(g.createLine(a, b), isNull);
    expect(g.money, plain.startMoney, reason: 'nothing charged when blocked');
    expect(g.zoneAt(const Offset(160, 100)), z);
    g.buyZone(z);
    expect(g.money, plain.startMoney - 100);
    expect(g.createLine(a, b), isNotNull);
    expect(g.zoneAt(const Offset(160, 100)), isNull);

    for (var i = 0; i < 20; i++) {
      final nz = g.spawnZone();
      if (nz == null) continue;
      expect(nz.cells.length, inInclusiveRange(3, 4));
      expect(routeHits(pathBetween(a.pos, b.pos), nz.contains), isFalse, reason: 'never on existing track');
      for (final c in nz.cells) {
        expect(hexNeighbors(c).any(nz.cells.contains), isTrue, reason: 'cells touch');
      }
    }
  });

  test('hex grid: cells round-trip and neighbours are one cell apart', () {
    for (final h in [(0, 0), (3, -2), (-4, 7), (10, 5)]) {
      expect(hexAt(hexCenter(h)), h);
      for (final n in hexNeighbors(h)) {
        expect((hexCenter(n) - hexCenter(h)).distance, closeTo(hexRadius * sqrt(3), 1e-9));
      }
      // a point just inside a corner still belongs to the cell
      final corner = hexCorners(h).first;
      expect(hexAt(Offset.lerp(hexCenter(h), corner, 0.95)!), h);
    }
  });

  test('sea blocks cheap routes: crossing a coast costs a bridge', () {
    final g = Game(cities.firstWhere((c) => c.name == 'Makassar'), spawn: false);
    expect(g.crossesWater(const Offset(100, 300), const Offset(400, 300)), isTrue);
    expect(g.crossesWater(const Offset(400, 300), const Offset(600, 300)), isFalse);
  });

  test('passenger transfers between lines, gets delivered, fare is paid', () {
    final g = Game(plain, spawn: false);
    // circle — triangle on the left bank, square next to it: no river crossing.
    final a = g.addStation(const Offset(60, 100), Shape.circle);
    final b = g.addStation(const Offset(160, 100), Shape.triangle);
    final c = g.addStation(const Offset(160, 250), Shape.square);

    const seg = Game.segmentCost;
    expect(g.createLine(a, b), isNotNull);
    expect(g.money, plain.startMoney - seg, reason: 'first line free, pay the segment');
    final red = g.createLine(b, c)!;
    final spent = 2 * seg + Game.lineCostStep;
    expect(g.money, plain.startMoney - spent);
    expect(red.stops, [b, c]);

    a.waiting.add(Shape.square); // must ride a->b then transfer b->c
    for (var i = 0; i < 2000 && g.delivered == 0; i++) {
      g.tick(0.05);
    }
    expect(g.delivered, 1);
    expect(g.fare, plain.normalFare);
    expect(g.money, plain.startMoney - spent + g.fare);
    expect(a.waiting, isEmpty);
  });

  test('festival event: hosted by an existing station, extra riders head only there, lasts one day', () {
    final g = Game(plain, seed: 5, spawn: false);
    final b = g.addStation(const Offset(100, 100), Shape.triangle);
    final d = g.addStation(const Offset(190, 100), Shape.circle);
    final host = g.addStation(const Offset(280, 100), Shape.circle);
    final off = g.addStation(const Offset(100, 250), Shape.square); // not on any line

    expect(g.startFestival(), isTrue);
    expect(g.stations.length, 4, reason: 'no new station');
    expect(g.popups.single.$1, '🎉');
    expect(g.startFestival(), isFalse, reason: 'one event at a time');
    for (final s in g.stations) {
      expect(s.waiting, s == g.festivalAt ? isEmpty : List.filled(Game.festivalBurst, Shape.festival),
          reason: 'the rush starts at once');
      s.waiting.clear();
    }
    g.festivalAt = host; // pin the random pick for the rest of the test

    for (var i = 0; i < 400; i++) {
      g.spawnPassenger();
    }
    final all = [for (final s in g.stations) if (s != host) ...s.waiting];
    final share = all.where((w) => w == Shape.festival).length / all.length;
    expect(share, closeTo(Game.festivalBoost / (1 + Game.festivalBoost), 0.08));
    expect(host.waiting.contains(Shape.festival), isFalse);
    for (final s in g.stations) {
      s.waiting.clear();
    }

    // Goes past another circle (d) and is only delivered at the host.
    b.waiting.add(Shape.festival);
    g.extend(g.createLine(b, d)!, host, atHead: false);
    for (var i = 0; i < 400 && g.delivered == 0; i++) {
      g.tick(0.05);
    }
    expect(g.delivered, 1);
    expect(d.waiting, isEmpty);

    // Time up: closed to new visitors, but it stays until those on their way are gone.
    g.tick(g.festivalLeft - 0.5);
    expect(g.festivalOpen, isTrue);
    off.waiting.add(Shape.festival);
    g.tick(1);
    expect(g.festivalOpen, isFalse);
    expect(g.festival, isNotNull, reason: 'a visitor is still on the way');
    expect(g.festivalAt, host);
    for (var i = 0; i < 100; i++) {
      g.spawnPassenger();
    }
    expect(g.festivalRiders, 1, reason: 'no new visitors once closed');
    for (var i = 0; i < 1200 && g.festival != null; i++) {
      g.tick(0.05); // off is on no line: the visitor gives up waiting
    }
    expect(g.festival, isNull, reason: 'gone once the last visitor left');
    expect(off.waiting.contains(Shape.festival), isFalse);
  });

  test('an event makes the whole city spawn more riders', () {
    int spawnedIn10s(bool event) {
      final g = Game(plain, seed: 9);
      if (event) g.startFestival();
      for (var i = 0; i < 200; i++) {
        g.tick(0.05);
      }
      return g.stations.fold(0, (n, s) => n + s.waiting.length);
    }

    expect(spawnedIn10s(true), greaterThan(spawnedIn10s(false) * 2));
  });

  test('accident: fine is owed even into debt, the train stalls', () {
    final g = Game(plain, seed: 1, spawn: false);
    final a = g.addStation(const Offset(60, 100), Shape.circle);
    final b = g.addStation(const Offset(260, 100), Shape.triangle);
    g.createLine(a, b);
    g.money = 100;
    final t = g.accident()!;
    expect(g.money, lessThan(0));
    expect(g.popups.single.$2, 'Kecelakaan kereta!');
    g.tick(1);
    expect(t.along, 0, reason: 'stuck');
    g.tick(Game.accidentStall);
    for (var i = 0; i < 10; i++) {
      g.tick(0.05);
    }
    expect(t.along, greaterThan(0), reason: 'moving again');
  });

  test('a wreck blocks its segment: trains behind and oncoming stop short, then carry on', () {
    final g = Game(plain, spawn: false);
    final a = g.addStation(const Offset(60, 100), Shape.circle);
    final b = g.addStation(const Offset(260, 100), Shape.triangle); // 200px apart
    final l = g.createLine(a, b)!;
    final crashed = l.trains.single..along = 100; // mid-segment, heading a -> b
    final behind = Train(l); // at a, heading a -> b
    final oncoming = Train(l)..dir = -1; // at b, heading b -> a
    l.trains.addAll([behind, oncoming]);

    g.accident(crashed);
    expect(l.blocked, hasLength(1));
    for (var i = 0; i < 100; i++) {
      g.tick(0.05); // 5s, wreck still there
    }
    expect(behind.along, closeTo(100 - Game.crashGap, 1e-9));
    expect(oncoming.along, closeTo(100 - Game.crashGap, 1e-9));
    expect(crashed.along, 100);

    for (var i = 0; i < 200; i++) {
      g.tick(0.05); // wreck cleared after 10s
    }
    expect(l.blocked, isEmpty);
    expect(crashed.along, isNot(100), reason: 'everyone moves again');
    expect(behind.seg != 0 || behind.dir != 1 || behind.along > 100, isTrue, reason: 'passed the old wreck');
  });

  test('closing a busy line: trains finish their trips, take nobody new, then the line disappears', () {
    final g = Game(plain, spawn: false);
    final a = g.addStation(const Offset(60, 100), Shape.circle);
    final b = g.addStation(const Offset(160, 100), Shape.triangle);
    final c = g.addStation(const Offset(260, 100), Shape.square);
    final l = g.createLine(a, b)!;
    g.extend(l, c, atHead: false);
    final t = l.trains.single;
    t.riders.addAll([Shape.square, Shape.star]); // square is ahead; no star anywhere on the line
    a.waiting.add(Shape.triangle); // must not be picked up once closing

    g.closeLine(l);
    expect(g.lines, contains(l), reason: 'still running as a temporary route');
    expect(g.extend(l, g.addStation(const Offset(60, 250), Shape.star), atHead: true), isFalse);
    expect(g.capAt(g.capTip(l, head: false)), isNull, reason: 'cannot grab a closing line');
    g.addTrain(l);
    expect(l.trains, [t], reason: 'no new trains on a closing line');

    for (var i = 0; i < 400 && g.lines.isNotEmpty; i++) {
      g.tick(0.05);
    }
    expect(g.lines, isEmpty, reason: 'gone once its last train is empty at a station');
    expect(g.delivered, 1, reason: 'the square rider still got there');
    expect(b.waiting, [Shape.star], reason: 'star rider was dropped off at the first stop to transfer');
    expect(a.waiting, [Shape.triangle], reason: 'nobody new boarded');
    expect(g.nextColor, l.color, reason: 'colour is free again');
  });

  test('rupiah formatting and city purchasing power', () {
    expect(rp(24000), 'Rp24.000');
    expect(rp(-1500), '-Rp1.500');
    expect(rp(500), 'Rp500');
    final jkt = Game(cities.last, spawn: false)..fare = 500;
    final mdn = Game(cities.first, spawn: false)..fare = 500;
    expect(jkt.patience, Game.waitLimit, reason: 'Rp500 is normal in Jakarta');
    expect(mdn.patience, lessThan(Game.waitLimit), reason: 'pricey in Medan: riders want a fast pickup');
    expect(mdn.spawnInterval, 9, reason: 'fare no longer thins out riders');
  });

  test('cheap fares make riders patient, pricey fares impatient', () {
    double ringAfter1s(int fare) {
      final g = Game(plain, spawn: false)..fare = fare;
      final a = g.addStation(const Offset(60, 100), Shape.circle);
      g.addStation(const Offset(160, 100), Shape.triangle);
      a.waiting.add(Shape.triangle);
      g.tick(1);
      return a.wait;
    }

    final normal = plain.normalFare;
    expect(ringAfter1s(normal), closeTo(1, 1e-9));
    expect(ringAfter1s(normal ~/ 2), closeTo(0.5, 0.01), reason: 'half price: twice as patient');
    expect(ringAfter1s(normal * 2), closeTo(2, 1e-9), reason: 'double price: fills twice as fast');
  });

  test('track shape is the same in both directions', () {
    const a = Offset(490, 457), b = Offset(817, 868);
    expect(pathBetween(b, a), pathBetween(a, b).reversed.toList());
  });

  test('bridge spans cover exactly the stretch over the river', () {
    final g = Game(plain, spawn: false);
    final west = g.addStation(const Offset(100, 300), Shape.circle);
    final east = g.addStation(const Offset(800, 300), Shape.triangle);
    // Straight track at y=300 meets the river centreline (330,200)-(520,380) near x=436; width 34.
    final spans = g.bridgeSpans(east, west); // order doesn't matter
    expect(spans, hasLength(1));
    final (from, to) = spans.single;
    final mid = 100 + (from + to) / 2; // key.$1 is west (lower id), route starts at x=100
    expect(mid, closeTo(436, 6));
    expect(to - from, inInclusiveRange(34, 60), reason: 'diagonal river is wider along a horizontal track');
    expect(g.bridgeSpans(west, g.addStation(const Offset(200, 300), Shape.square)), isEmpty);
  });

  test('rerouting bridged track reuses the bridge: no fee, no rebuild', () {
    final g = Game(plain, spawn: false)..money = 100000;
    final west = g.addStation(const Offset(100, 300), Shape.circle);
    final east = g.addStation(const Offset(800, 300), Shape.triangle);
    final l = g.createLine(west, east)!;
    g.tick(Game.tunnelBuildTime + 1);
    expect(l.building, isEmpty, reason: 'bridge finished');

    // New stop on the east bank: west–m crosses on the very same deck (y=300), m–east stays dry.
    final m = g.addStation(const Offset(600, 330), Shape.square);
    final before = g.money;
    expect(g.insert(l, 0, m), isTrue);
    expect(g.bridgeSpans(west, m), isNotEmpty);
    expect(g.bridgeSpans(m, east), isEmpty);
    expect(g.money, before - 2 * Game.segmentCost, reason: 'no bridge fee: old bridge reused');
    expect(l.building, isEmpty, reason: 'no rebuild');

    // Same river, far away: the old deck is at ~(540,500); m2 sits on the west bank far
    // upstream, so m2–east crosses at ~(315,100), way past Game.bridgeReach. A new bridge.
    final l2 = g.createLine(g.addStation(const Offset(100, 500), Shape.circle), east)!;
    g.tick(Game.tunnelBuildTime + 1);
    final m2 = g.addStation(const Offset(150, 100), Shape.square);
    final before3 = g.money;
    expect(g.insert(l2, 0, m2), isTrue);
    expect(g.money, before3 - 2 * Game.segmentCost - plain.bridgeCost, reason: 'a different bridge, so it is paid');
    expect(l2.building.keys, [MetroLine.key(m2, east)]);

    // A dry segment rerouted across the river (there and back) pays for both new bridges.
    final w2 = g.addStation(const Offset(100, 150), Shape.star);
    final dry = g.createLine(west, w2)!;
    final far = g.addStation(const Offset(700, 200), Shape.diamond);
    final before2 = g.money;
    expect(g.insert(dry, 0, far), isTrue);
    expect(g.money, before2 - 2 * Game.segmentCost - 2 * plain.bridgeCost);
    expect(dry.building, hasLength(2), reason: 'new bridges must be built');
  });

  test('rerouting through several stops: bridges are matched against the final route only', () {
    final g = Game(plain, spawn: false);
    final a = g.addStation(const Offset(200, 330), Shape.circle);
    final b = g.addStation(const Offset(700, 330), Shape.triangle);
    final l = g.createLine(a, b)!;
    g.tick(20); // bridge finished
    // a -> s1 -> s2 -> b: only s2–b crosses, right over the old deck. (Inserting s1 alone
    // would cross elsewhere via s1–b, which must not be charged or built.)
    final s1 = g.addStation(const Offset(300, 450), Shape.square);
    final s2 = g.addStation(const Offset(420, 330), Shape.star);
    expect(g.bridgeSpans(s1, b), isNotEmpty);
    final plan = g.planCost(a, [s1, s2], line: l, seg: 0);
    final before = g.money;
    expect(g.reroute(l, 0, [s1, s2]), isTrue);
    expect(l.stops, [a, s1, s2, b]);
    expect(before - g.money, 3 * Game.segmentCost, reason: 'three new segments, old bridge reused');
    expect(plan, before - g.money, reason: 'the plan shows exactly what is charged');
    expect(l.building, isEmpty, reason: 'the reused bridge is not rebuilt');
  });

  test('Medan: rerouting a two-bridge track through a station on the island between the rivers '
      'keeps both bridges', () {
    // Track west -> east crosses the Babura and then the Deli. Wherever the island stop is,
    // each new segment crosses one of those rivers near its old bridge: both are reused.
    for (final island in const [Offset(500, 450), Offset(480, 560), Offset(520, 380), Offset(450, 600)]) {
      final g = Game(cities.first, spawn: false)..money = 100000;
      final a = g.addStation(const Offset(250, 500), Shape.circle);
      final b = g.addStation(const Offset(750, 500), Shape.triangle);
      final l = g.createLine(a, b)!;
      g.tick(20);
      expect(g.bridgeSpans(a, b), hasLength(2));
      final m = g.addStation(island, Shape.square);
      final plan = g.planCost(a, [m], line: l, seg: 0);
      final before = g.money;
      expect(g.insert(l, 0, m), isTrue);
      expect(before - g.money, 2 * Game.segmentCost, reason: 'island at $island: no bridge fee');
      expect(plan, before - g.money);
      expect(l.building, isEmpty, reason: 'island at $island: nothing to rebuild');
    }
  });

  test('crossing the same river twice needs a second bridge', () {
    final g = Game(plain, spawn: false)..money = 100000;
    final a = g.addStation(const Offset(200, 330), Shape.circle);
    final b = g.addStation(const Offset(700, 330), Shape.triangle); // east bank
    final l = g.createLine(a, b)!;
    g.tick(20);
    // a -> e (east bank) -> w (west bank) -> b: three crossings where there was one.
    final e = g.addStation(const Offset(560, 250), Shape.square);
    final w = g.addStation(const Offset(380, 420), Shape.star);
    final before = g.money;
    expect(g.reroute(l, 0, [e, w]), isTrue);
    expect(before - g.money, 3 * Game.segmentCost + 2 * plain.bridgeCost, reason: 'one reused, two new');
    expect(l.building, hasLength(2));
  });

  test('rerouting an unfinished bridge keeps its remaining build time', () {
    final g = Game(plain, spawn: false)..money = 100000;
    final west = g.addStation(const Offset(100, 300), Shape.circle);
    final east = g.addStation(const Offset(800, 300), Shape.triangle);
    final l = g.createLine(west, east)!;
    g.tick(5);
    final left = l.building.values.single;
    final m = g.addStation(const Offset(600, 330), Shape.square);
    g.insert(l, 0, m);
    expect(l.building, {MetroLine.key(west, m): left});
  });

  test('detaching a station: middle rejoins neighbours, ends shorten, trains stay valid', () {
    final g = Game(plain, spawn: false);
    final st = [for (var i = 0; i < 4; i++) g.addStation(Offset(60 + i * 70.0, 100), Shape.values[i])];
    final l = g.createLine(st[0], st[1])!;
    for (final s in st.skip(2)) {
      g.extend(l, s, atHead: false);
    }
    // Trains touching st[1] (both sides) and one further along.
    l.trains
      ..clear()
      ..addAll([
        Train(l)..seg = 0..along = 30, // st0 -> st1
        Train(l)..seg = 1..dir = -1..along = 20, // st2 -> st1
        Train(l)..seg = 2..along = 10, // st2 -> st3
      ]);
    final money = g.money;

    expect(g.detach(l, 1), isTrue);
    expect(l.stops, [st[0], st[2], st[3]]);
    expect(g.money, money, reason: 'dry land: detaching is free');
    for (final t in l.trains) {
      expect(() => (t.from, t.to), returnsNormally);
    }
    expect((l.trains[2].from, l.trains[2].to), (st[2], st[3]), reason: 'untouched train keeps its track');

    expect(g.detach(l, 2), isTrue, reason: 'tail end');
    expect(l.stops, [st[0], st[2]]);
    expect(g.detach(l, 0), isFalse, reason: 'a line keeps at least 2 stations');
    for (var i = 0; i < 100; i++) {
      g.tick(0.05); // trains keep running without errors
    }
  });

  test('detaching a station keeps a bridge the new track runs over, pays for a new one', () {
    final g = Game(plain, spawn: false)..money = 100000;
    final west = g.addStation(const Offset(100, 300), Shape.circle);
    final mid = g.addStation(const Offset(600, 300), Shape.square); // east bank
    final east = g.addStation(const Offset(800, 300), Shape.triangle);
    final l = g.createLine(west, mid)!;
    g.extend(l, east, atHead: false);
    g.tick(Game.tunnelBuildTime + 1);
    final money = g.money;
    expect(g.detach(l, 1), isTrue);
    expect(g.money, money, reason: 'west–east runs over the same deck as west–mid');
    expect(l.building, isEmpty);

    // Detaching a dry-land stop whose neighbours sit across the river: a–c crosses at
    // ~(328,188), far from the old b–c bridge at ~(550,560). A new bridge.
    final a = g.addStation(const Offset(150, 100), Shape.star);
    final b = g.addStation(const Offset(250, 560), Shape.diamond); // west bank
    final c = g.addStation(const Offset(700, 560), Shape.circle); // east bank
    final l2 = g.createLine(a, b)!;
    g.extend(l2, c, atHead: false);
    g.tick(Game.tunnelBuildTime + 1);
    final money2 = g.money;
    expect(g.detach(l2, 1), isTrue);
    expect(g.money, money2 - plain.bridgeCost, reason: 'a–c crosses somewhere b–c did not');
    expect(l2.building.keys, [MetroLine.key(a, c)]);
  });

  test('bridges cost extra and purchases never overdraw', () {
    final g = Game(plain, spawn: false);
    final west = g.addStation(const Offset(100, 300), Shape.circle);
    final east = g.addStation(const Offset(800, 300), Shape.triangle);
    expect(g.crossesWater(west.pos, east.pos), isTrue);
    g.createLine(west, east);
    expect(g.money, plain.startMoney - Game.segmentCost - plain.bridgeCost);

    g.money = 10;
    final l = g.lines.single;
    g.addTrain(l);
    expect(l.trains.length, 1);
    expect(g.money, 10);
  });

  test('anger: each rider walking off adds 1; it drains after 5 s of calm; too much ends the city', () {
    final g = Game(plain, spawn: false);
    final a = g.addStation(const Offset(60, 100), Shape.circle);
    void walkOff() {
      a.waiting.add(Shape.square);
      a.wait = Game.waitLimit;
      a.giveUp = a.giveUpInterval;
      g.tick(0.001);
    }

    walkOff();
    g.tick(0.1);
    walkOff();
    expect(g.anger, 2, reason: '+1 per rider, even 100 ms apart');
    g.tick(Game.angerHold - 0.5);
    expect(g.anger, 2, reason: 'no drain within 5 s');
    g.tick(1.5);
    expect(g.anger, lessThan(2), reason: 'then it drains slowly');
    g.tick(5);
    expect(g.anger, 0, reason: 'down to 0');
    walkOff();
    expect(g.anger, 1, reason: 'and climbs again');
    for (var i = 0; i < Game.angerLimit; i++) {
      walkOff();
    }
    expect(g.gameOver, isNotNull);
  });

  test('upkeep charged monthly, bankruptcy ends game', () {
    final g = Game(plain, spawn: false);
    final a = g.addStation(const Offset(60, 100), Shape.circle);
    final b = g.addStation(const Offset(160, 100), Shape.triangle);
    g.createLine(a, b);
    g.money = Game.debtLimit + 5;
    for (var i = 0; i < Game.monthLength / 0.05 + 2; i++) {
      g.tick(0.05);
    }
    expect(g.lastCost, Game.trainUpkeep + Game.lineUpkeep);
    expect(g.gameOver, isNotNull);
  });

  test('extending at head keeps trains on their segment', () {
    final g = Game(plain, spawn: false);
    final a = g.addStation(const Offset(60, 100), Shape.circle);
    final b = g.addStation(const Offset(160, 100), Shape.triangle);
    final z = g.addStation(const Offset(60, 250), Shape.square);
    final l = g.createLine(a, b)!;
    final t = l.trains.single;
    expect(g.extend(l, z, atHead: true), isTrue);
    expect(l.stops, [z, a, b]);
    expect((t.from, t.to), (a, b));
    expect(g.extend(l, a, atHead: false), isFalse, reason: 'no loops');
  });

  test('inserting a station mid-line reroutes trains onto the new track', () {
    final g = Game(plain, spawn: false);
    final a = g.addStation(const Offset(60, 100), Shape.circle);
    final b = g.addStation(const Offset(160, 100), Shape.triangle);
    final c = g.addStation(const Offset(260, 100), Shape.square);
    final m = g.addStation(const Offset(110, 250), Shape.star);
    final l = g.createLine(a, b)!;
    g.extend(l, c, atHead: false);
    final fwd = l.trains.single;
    final back = Train(l)..dir = -1; // heading b -> a
    final far = Train(l)..seg = 1; // on b -> c
    l.trains.addAll([back, far]);
    final before = g.money;

    expect(g.insert(l, 0, m), isTrue);
    expect(l.stops, [a, m, b, c]);
    expect(g.money, before - 2 * Game.segmentCost);
    expect((fwd.from, fwd.to), (a, m));
    expect((back.from, back.to), (b, m));
    expect((far.from, far.to), (b, c));
    expect(g.insert(l, 0, c), isFalse, reason: 'already on the line');
  });
}
