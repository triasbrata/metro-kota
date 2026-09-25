import 'dart:math';
import 'dart:ui' show Picture, PictureRecorder;

import 'package:flutter/material.dart';

import 'game.dart';

const ink = Color(0xFF2B2B2B);
const festivalColor = Color(0xFF9B30D9);
const festivalOnTrain = Color(0xFFE2B8FF); // lighter purple, readable on the dark train body

class GamePainter extends CustomPainter {
  GamePainter(this.game, this.origin, this.scale,
      {this.selected, this.drag, this.detach, this.trainDrag, this.carDrag});

  /// Carriage being dragged onto a train: the finger, the train it would hook onto (ringed),
  /// and whether it is affordable.
  final (Offset finger, Offset? target, bool affordable)? carDrag;
  final Game game;
  final Offset origin;
  final double scale;
  final MetroLine? selected;
  /// Track being planned: the route to draw, where the finger is, and the cost so far.
  final (List<Offset> chain, Offset finger, Color color, String cost, bool affordable)? drag;

  /// Station being held to detach it from a line, and how far the hold has got (1 = armed).
  final (Offset at, double progress)? detach;

  /// New train being dragged in: the finger, and (over a track) the spot it snaps to with
  /// its heading. Drawn faded, with an arrow showing which way it will run.
  /// [label]: its price, or what happens (moving a train is free).
  final (Offset finger, (Offset at, double heading, Color color)? snap, bool affordable, String label)? trainDrag;

  /// Land, hex grid, water and permit zones only change with the camera or a zone, so they
  /// are recorded once and replayed every frame.
  static (Object key, Picture picture)? _backdrop;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final key = (game, origin, scale, size, game.zones.where((z) => !z.paid).length);
    if (_backdrop?.$1 != key) {
      final recorder = PictureRecorder();
      _paintBackdrop(Canvas(recorder), size);
      _backdrop?.$2.dispose();
      _backdrop = (key, recorder.endRecording());
    }
    canvas.drawPicture(_backdrop!.$2);
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);

    _lanes = laneLayout(game.lines, gap: _laneGap);
    for (final l in game.lines) {
      _line(canvas, l);
    }
    _paintDynamic(canvas);
  }

  void _paintBackdrop(Canvas canvas, Size size) {
    // The land fills the whole view (no letterbox band beside the map), and water touching
    // the map's edge runs on to the edge of the screen.
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFF4F2EE));
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);
    // Faint hex grid over the land: permit zones are made of these cells, so they never
    // appear out of nowhere. Water is painted over it.
    final view = Rect.fromLTWH(-origin.dx / scale, -origin.dy / scale, size.width / scale, size.height / scale);
    final grid = Path();
    final rowH = hexRadius * 1.5, colW = hexRadius * sqrt(3);
    for (var r = (view.top / rowH).floor() - 1; r <= (view.bottom / rowH).ceil() + 1; r++) {
      for (var q = (view.left / colW - r / 2).floor() - 1; q <= (view.right / colW - r / 2).ceil() + 1; q++) {
        grid.addPolygon(hexCorners((q, r)), true);
      }
    }
    canvas.drawPath(grid, _stroke(ink.withValues(alpha: .07), 1));
    const water = Color(0xFF9DB9DC);
    for (final w in game.city.water) {
      canvas.drawPath(
        Path()..addPolygon([for (final p in w.points) _bleed(p)], w.sea),
        w.sea ? (Paint()..color = water) : (_stroke(water, w.width)..strokeCap = StrokeCap.butt),
      );
    }

    for (final z in game.zones.where((z) => !z.paid)) {
      final cells = Path();
      for (final c in z.cells) {
        cells.addPolygon(hexCorners(c), true);
      }
      canvas.drawPath(cells, Paint()..color = const Color(0x33E67E22));
      canvas.drawPath(cells, _stroke(const Color(0xAAE67E22), 2));
      final label = TextPainter(
        text: TextSpan(
          text: '${z.name}\nIzin ${rp(z.price)}',
          style: const TextStyle(color: Color(0xFF9A4A0B), fontSize: 13, fontWeight: FontWeight.w700),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: hexRadius * 4);
      label.paint(canvas, z.center - Offset(label.width / 2, label.height / 2));
    }
  }

  void _paintDynamic(Canvas canvas) {
    if (drag case (final chain, _, final c, _, _)) {
      final plan = Path();
      for (var i = 0; i + 1 < chain.length; i++) {
        plan.addPolygon(pathBetween(chain[i], chain[i + 1]), false);
      }
      canvas.drawPath(plan, _stroke(c.withValues(alpha: .5), 8));
    }
    for (final l in game.lines) {
      for (final t in l.trains.where((t) => !t.held)) {
        // (a held train is in the player's hand: drawn as the trainDrag ghost instead)
        _train(canvas, t);
      }
    }
    // Crash sites: a red "!" sign floating above the blocked track, over the trains.
    for (final l in game.lines) {
      for (final MapEntry(key: (a, b), value: wreck) in l.blocked.entries) {
        final (p, _) = pointAlong(l.route(a, b), wreck);
        final sign = p + const Offset(0, -34);
        canvas.drawLine(p + const Offset(0, -12), sign, _stroke(ink, 2));
        canvas.drawCircle(sign, 12, Paint()..color = Colors.red.shade700);
        canvas.drawCircle(sign, 12, _stroke(Colors.white, 2));
        canvas.drawLine(sign + const Offset(0, -6), sign + const Offset(0, 2), _stroke(Colors.white, 3));
        canvas.drawCircle(sign + const Offset(0, 6.5), 1.8, Paint()..color = Colors.white);
      }
    }
    for (final s in game.stations) {
      _station(canvas, s);
    }
    // Hold-to-detach: a ring fills around the station; red with "Lepas" once armed.
    if (detach case (final at, final progress)) {
      final armed = progress >= 1;
      final ring = _stroke(armed ? Colors.red.shade700 : ink, 4);
      canvas.drawArc(Rect.fromCircle(center: at, radius: 30), -pi / 2, 2 * pi * progress, false, ring);
      if (armed) {
        final label = TextPainter(
          text: TextSpan(
            text: 'Lepas',
            style: TextStyle(color: Colors.red.shade700, fontSize: 13, fontWeight: FontWeight.w800),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(canvas, at + Offset(-label.width / 2, 34));
      }
    }
    if (trainDrag case (final finger, final snap, _, _)) {
      final (at, heading, color) = snap ?? (finger, 0.0, Colors.grey);
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(heading);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 30, height: 16), const Radius.circular(3)),
        Paint()..color = Color.lerp(color, ink, .25)!.withValues(alpha: snap == null ? .4 : .75),
      );
      if (snap != null) {
        // Arrow ahead of the train: its direction of travel.
        final arrow = Path()
          ..moveTo(22, -9)
          ..lineTo(36, 0)
          ..lineTo(22, 9)
          ..close();
        canvas.drawPath(arrow, Paint()..color = ink);
      }
      canvas.restore();
    }
    if (carDrag case (final finger, final target, _)) {
      if (target != null) canvas.drawCircle(target, 26, _stroke(ink, 3));
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: finger, width: 28, height: 16), const Radius.circular(3)),
        Paint()..color = ink.withValues(alpha: target == null ? .35 : .7),
      );
    }
    // Cost of the plan so far, next to the finger; red when there isn't enough money.
    final label = switch ((drag, trainDrag, carDrag)) {
      ((_, final finger, _, final cost, final affordable), _, _) when cost.isNotEmpty => (finger, cost, affordable),
      (_, (final finger, _, final affordable, final label), _) => (finger, label, affordable),
      (_, _, (final finger, _, final affordable)) => (finger, rp(Game.carCost), affordable),
      _ => null,
    };
    if (label case (final finger, final cost, final affordable)) {
      final label = TextPainter(
        text: TextSpan(
          text: cost,
          style: TextStyle(color: affordable ? ink : Colors.red.shade700, fontSize: 14, fontWeight: FontWeight.w800),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final box = Rect.fromLTWH(finger.dx + 18, finger.dy - 34, label.width + 12, label.height + 6);
      canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(8)), Paint()..color = Colors.white);
      canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(8)), _stroke(ink, 1));
      label.paint(canvas, box.topLeft + const Offset(6, 3));
    }
  }

  /// Pushes a point lying on the map's border far outwards, so rivers and seas that reach the
  /// border keep going past it.
  static Offset _bleed(Offset p) {
    const far = 5000.0;
    double out(double v, double max) => v <= 0 ? -far : (v >= max ? max + far : v);
    return Offset(out(p.dx, worldSize.width), out(p.dy, worldSize.height));
  }

  Paint _stroke(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  /// Lanes where lines share track (see [laneLayout]): computed once per frame in [paint].
  var _lanes = <(MetroLine, int), List<Lane>>{};
  static const _laneGap = 8.0; // = the track width: lanes lie side by side, touching

  void _line(Canvas canvas, MetroLine l) {
    // A closing line is a faded temporary route until its trains finish. Where it shares
    // track with other lines it runs in its own lane beside them, just as wide.
    final paint = _stroke(l.closing ? l.color.withValues(alpha: .35) : l.color, l == selected ? 11 : 8);
    final w = paint.strokeWidth;
    final track = Path();
    for (var i = 0; i + 1 < l.stops.length; i++) {
      final pts = _laneTrack(l.route(l.stops[i], l.stops[i + 1]), _lanes[(l, i)]);
      if (!l.isBuilding(l.stops[i], l.stops[i + 1])) {
        _addRounded(track, pts);
      } else {
        // Under construction: faded track.
        final p = Path();
        _addRounded(p, pts);
        canvas.drawPath(p, _stroke(l.color.withValues(alpha: .3), w));
      }
    }
    canvas.drawPath(track, paint);

    // Bridges: black rails on both sides wherever the track is over water (around the whole
    // band where lines share it). While one is being built, its deck is the progress bar: it
    // fills with the line colour along the track.
    for (var i = 0; i + 1 < l.stops.length; i++) {
      final key = MetroLine.key(l.stops[i], l.stops[i + 1]);
      final spans = game.bridgeSpans(key.$1, key.$2, l.bends[key]); // distances along the key's route
      if (spans.isEmpty) continue;
      final route = l.route(l.stops[i], l.stops[i + 1]);
      final len = pathLength(route), flip = key.$1 != l.stops[i];
      final left = l.building[key];
      for (final span in spans) {
        final (from, to) = flip ? (len - span.$2, len - span.$1) : span;
        // the deck reaches a little past the banks, like a real bridge
        final a = max(0.0, from - 8), b = min(len, to + 8);
        final lane = laneAt(_lanes[(l, i)], (a + b) / 2);
        final shift = lane?.shift ?? Offset.zero, shared = lane?.shared ?? 1;
        if (left != null) {
          final deck = _stroke(Colors.white, w)..strokeCap = StrokeCap.butt;
          canvas.drawPath(Path()..addPolygon([for (final p in _trace(route, a, b)) p + shift], false), deck);
          final built = a + (b - a) * (1 - left / Game.tunnelBuildTime);
          if (built > a) {
            canvas.drawPath(
                Path()..addPolygon([for (final p in _trace(route, a, built)) p + shift], false), deck..color = l.color);
          }
        }
        final railOff = (shared - 1) / 2 * _laneGap + w / 2 + 4;
        final rail = _stroke(ink, 2.5)..strokeCap = StrokeCap.butt;
        canvas.drawPath(Path()..addPolygon(_trace(route, a, b, railOff), false), rail);
        canvas.drawPath(Path()..addPolygon(_trace(route, a, b, -railOff), false), rail);
      }
    }
    // Terminal "T" caps show where a line can be extended (a loop has no ends).
    for (final head in [if (!l.loop) ...[true, false]]) {
      final end = head ? l.stops.first : l.stops.last;
      final tip = game.capTip(l, head: head);
      final u = (tip - end.pos) / 26;
      final n = Offset(-u.dy, u.dx) * 10;
      canvas.drawLine(end.pos, tip, paint);
      canvas.drawLine(tip - n, tip + n, paint);
    }
  }

  /// [route] pushed into its lanes with [laneShift] (easing in and out), as the corner
  /// points of the shifted track: it is exactly straight between the route's own corners
  /// and where the lane shift bends.
  List<Offset> _laneTrack(List<Offset> route, List<Lane>? lanes) {
    if (lanes == null) return route;
    final len = pathLength(route);
    final at = <double>{0, len, ...laneKnots(lanes, len)};
    // A corner shared on both sides sits where the two lane lines meet (their miter), so
    // the lane turns once, cleanly, instead of cutting the corner in two small kinks.
    final miters = <double, Offset>{};
    var run = 0.0;
    for (var i = 1; i + 1 < route.length; i++) {
      at.add(run += (route[i] - route[i - 1]).distance);
      final z1 = laneAt(lanes, run - laneEase), z2 = laneAt(lanes, run + laneEase);
      final u1 = route[i] - route[i - 1], u2 = route[i + 1] - route[i];
      final cross = u1.dx * u2.dy - u1.dy * u2.dx;
      if (z1 == null || z2 == null || cross.abs() < 1e-6) continue;
      final d = z2.shift - z1.shift, t = (d.dx * u2.dy - d.dy * u2.dx) / cross;
      miters[run] = route[i] + z1.shift + u1 * t;
    }
    return [for (final s in at.toList()..sort()) miters[s] ?? pointAlong(route, s).$1 + laneShift(lanes, s, len)];
  }

  /// Adds [pts] to [path] with every corner rounded off (radius [r], less on short pieces).
  static void _addRounded(Path path, List<Offset> pts, [double r = 14]) {
    if (pts.length < 2) return;
    path.moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i + 1 < pts.length; i++) {
      final a = pts[i - 1], v = pts[i], b = pts[i + 1];
      final da = (a - v).distance, db = (b - v).distance;
      final k = min(r, min(da, db) / 2);
      if (k < 0.5) {
        path.lineTo(v.dx, v.dy);
        continue;
      }
      final p = v + (a - v) / da * k, q = v + (b - v) / db * k;
      path
        ..lineTo(p.dx, p.dy)
        ..quadraticBezierTo(v.dx, v.dy, q.dx, q.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
  }

  /// Points along [route] from distance [from] to [to] (every 4px), each shifted [off]
  /// sideways; follows the track through its bend.
  List<Offset> _trace(List<Offset> route, double from, double to, [double off = 0]) {
    final pts = <Offset>[];
    for (var d = from;; d = min(to, d + 4)) {
      final (p, angle) = pointAlong(route, d);
      pts.add(p + Offset(-sin(angle), cos(angle)) * off);
      if (d >= to) break;
    }
    return pts;
  }

  void _train(Canvas canvas, Train t) {
    final body = Paint()..color = Color.lerp(t.line.color, ink, .25)!;
    final white = Paint()..color = Colors.white, eventRider = Paint()..color = festivalOnTrain;
    // Locomotive (k = 0), then each carriage further back along the track it came by, each
    // in the line's own lane where it shares track. 6 riders per car.
    for (var k = 0; k <= t.cars; k++) {
      final pose = trackBehind(t, k * Game.carPitch);
      final l = t.line, lanes = _lanes[(l, pose.seg)];
      final p = pose.pos +
          (lanes == null ? Offset.zero : laneShift(lanes, pose.s, pathLength(l.route(l.stops[pose.seg], l.stops[pose.seg + 1]))));
      if (k == 0 && t.broken > 0) {
        // Crashed: blinking red warning ring.
        final on = (t.broken * 3).floor().isEven;
        canvas.drawCircle(p, 22, _stroke(Colors.red.withValues(alpha: on ? .9 : .3), 4));
      }
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(pose.angle);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: k == 0 ? 30 : 28, height: 16),
            const Radius.circular(3)),
        body,
      );
      final seats = t.riders.skip(k * Game.trainCapacity).take(Game.trainCapacity).toList();
      for (final (slot, w) in seats.indexed) {
        drawShape(canvas, _drawnAs(w), Offset(-9 + (slot % 3) * 9, slot < 3 ? -3.5 : 3.5), 3,
            w == Shape.festival ? eventRider : white);
      }
      canvas.restore();
    }
  }

  void _station(Canvas canvas, Station s) {
    if (s.wait > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: s.pos, radius: 19),
        -pi / 2,
        2 * pi * min(1, s.wait / Game.waitLimit),
        false,
        _stroke(const Color(0xFFE8B83A), 3),
      );
    }
    final isEvent = s == game.festivalAt;
    drawShape(canvas, s.shape, s.pos, isEvent ? 16 : 13, Paint()..color = isEvent ? festivalColor : Colors.white);
    drawShape(canvas, s.shape, s.pos, isEvent ? 16 : 13, _stroke(ink, 4));
    final dot = Paint()..color = ink, eventDot = Paint()..color = festivalColor;
    for (var i = 0; i < s.waiting.length; i++) {
      final w = s.waiting[i];
      drawShape(canvas, _drawnAs(w), s.pos + Offset(22 + (i % 6) * 11, -6 + (i ~/ 6) * 11), 4.5,
          w == Shape.festival ? eventDot : dot);
    }
    // Upset riders here walk out faster (this station only).
    if (s.upset > 0.05) {
      final mood = TextPainter(
        text: TextSpan(text: '😠', style: TextStyle(fontSize: 12 + 3 * s.upset)),
        textDirection: TextDirection.ltr,
      )..layout();
      mood.paint(canvas, s.pos + Offset(-mood.width / 2, -26 - mood.height));
    }
  }

  /// Event riders look like the (purple) host station they are heading to.
  Shape _drawnAs(Shape w) => w == Shape.festival ? game.festivalAt?.shape ?? w : w;

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

void drawShape(Canvas canvas, Shape shape, Offset c, double r, Paint paint) {
  switch (shape) {
    case Shape.circle:
      canvas.drawCircle(c, r, paint);
    case Shape.square:
      canvas.drawRect(Rect.fromCircle(center: c, radius: r * .9), paint);
    case Shape.triangle:
      canvas.drawPath(_poly(c, r * 1.2, 3, -pi / 2, 1), paint);
    case Shape.diamond:
      canvas.drawPath(_poly(c, r * 1.2, 4, 0, 1), paint);
    case Shape.star:
      canvas.drawPath(_poly(c, r * 1.3, 5, -pi / 2, .45), paint);
    case Shape.festival:
      canvas.drawPath(_poly(c, r * 1.15, 6, 0, 1), paint);
  }
}

/// Regular polygon; inner < 1 makes it a star.
Path _poly(Offset c, double r, int n, double start, double inner) {
  final star = inner < 1;
  final count = star ? n * 2 : n;
  return Path()
    ..addPolygon([
      for (var i = 0; i < count; i++)
        c + Offset.fromDirection(start + 2 * pi * i / count, (star && i.isOdd) ? r * inner : r),
    ], true);
}
