import 'dart:math';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'game.dart';
import 'main.dart';
import 'painter.dart';
import 'settings.dart';
import 'sfx.dart';
import 'ui.dart';

/// Playing one city: the map (GamePainter) with the HUD drawn over it, all on the canvas.
class CityScene extends Scene {
  CityScene(this.city, {Game? resume}) : saved = resume;
  final City city;

  /// A saved game of [city] to carry on with, instead of starting afresh.
  final Game? saved;
  late Game game = saved ?? Game(city);

  // The city in progress is saved when the player leaves it, when the app goes to the
  // background (Android may kill it there), when the window is closed (desktop), and every
  // in-game week, so it can be resumed at any time.
  AppLifecycleListener? _lifecycle;
  static const _weekLength = Game.monthLength / 4;
  int _savedWeek = 0;
  void _save() => saveGame(game);

  @override
  void enter() {
    _lifecycle = AppLifecycleListener(
      onPause: _save,
      onHide: _save,
      onDetach: _save,
      onExitRequested: () async {
        await saveGame(game);
        return AppExitResponse.exit;
      },
    );
    Sounds.scene(Music.game);
  }

  @override
  void exit() {
    _save();
    if (game.won) recordRun(game); // left a cleared city: on to the next one, or out of endless
    _lifecycle?.dispose();
    Sounds.scene(Music.menu);
  }

  double speed = 1; // 0 = paused
  MetroLine? selected;

  // drag state
  Station? dragStart;
  MetroLine? dragLine;
  bool dragHead = false;
  int? dragSeg; // set when rerouting the track between stops[dragSeg] and stops[dragSeg + 1]
  Offset? finger;

  // camera: world -> screen is p * scale + origin; zoom/cam sit on top of the fit-to-screen view
  Offset origin = Offset.zero;
  double scale = 1;
  Size view = Size.zero;
  Offset fitOrigin = Offset.zero;
  double fitScale = 1;
  double zoom = 1;
  Offset cam = Offset.zero;
  static const maxZoom = 3.0;

  // two-finger pinch state
  bool pinching = false;
  double pinchZoom = 1;
  Offset pinchWorld = Offset.zero;

  @override
  void update(double dt) {
    _now += Duration(microseconds: (dt * 1e6).round());
    if (dt > 0) _frameMs = _frameMs == 0 ? dt * 1000 : _frameMs * 0.9 + dt * 1000 * 0.1; // smoothed
    if (_holdInPlan && _holdAt != null && _holdProgress >= 1) {
      planned.remove(_holdAt); // the finger is still inside it: re-adding needs out + in again
      _holdAt = null;
    }
    if (selected?.closing ?? false) selected = null;
    final wasWon = game.won, wasOver = game.gameOver != null;
    game.tick(min(dt, 0.05) * speed);
    if (!wasWon && game.won && !game.endless) {
      markCleared(city);
      game.sfx.add(Sfx.win);
    }
    if (!wasOver && game.gameOver != null) {
      game.sfx.add(Sfx.lose);
      recordRun(game);
    }
    game.sfx.forEach(Sounds.play);
    game.sfx.clear();
    final week = game.time ~/ _weekLength;
    if (week != _savedWeek || ((game.gameOver != null) != wasOver) || game.won != wasWon) {
      _savedWeek = week;
      _save(); // a finished city clears its save instead
    }
    if (popup == null && game.popups.isNotEmpty) _showPopup(game.popups.removeAt(0));
  }

  GamePainter get _painter => GamePainter(game, origin, scale,
      selected: selected,
      drag: _dragPreview,
      detach: _holdAt == null ? null : (_holdAt!.pos, _holdProgress),
      trainDrag: _trainPreview,
      carDrag: switch (carFinger) {
        final f? => (
            f,
            carTarget == null ? null : trackBehind(carTarget!, 0).pos,
            game.money >= Game.carCost,
          ),
        null => null,
      });

  // A carriage dragged from the left rail onto a train, or onto a track.
  Offset? carFinger; // world
  Train? carTarget;

  void _carDragMove(Offset screen) {
    final w = carFinger = _toWorld(screen);
    // Onto a train itself, or onto a track: then the line's train with the fewest carriages.
    carTarget = game.trainAt(w) ??
        switch (game.segmentAt(w, selected)) {
          (final l, _) => game.trainForCar(l, w),
          null => null,
        };
  }

  void _carDragEnd() {
    final t = carTarget, w = carFinger;
    carFinger = carTarget = null;
    if (t != null) {
      game.addCar(t);
    } else if (w != null) {
      game.notify(game.segmentAt(w, selected) != null
          ? 'Semua kereta di jalur ini sudah membawa ${Game.maxCars} gerbong'
          : 'Lepas gerbongnya di atas kereta atau rel jalurnya');
    }
  }

  // A train dragged onto a track: a new one from the left rail, or one lifted off the map
  // ([movingTrain], to turn it round or move it). Moving the finger along the track picks the
  // way it will run: towards stops[seg + 1] (1) or back towards stops[seg] (-1).
  Offset? trainFinger; // world
  (MetroLine, int seg, double at, double heading)? trainSpot;
  int trainDir = 1;
  Train? movingTrain;

  void _trainDragAt(Offset w, Offset delta) {
    trainFinger = w;
    final hit = game.segmentAt(w, movingTrain?.line ?? selected);
    if (hit == null) {
      trainSpot = null;
      return;
    }
    final (l, i) = hit;
    final (at, heading) = nearestAlong(l.route(l.stops[i], l.stops[i + 1]), w);
    final along = delta.dx * cos(heading) + delta.dy * sin(heading);
    final across = -delta.dx * sin(heading) + delta.dy * cos(heading);
    if (along.abs() > 0.5 && along.abs() > across.abs()) trainDir = along > 0 ? 1 : -1;
    trainSpot = (l, i, at, heading);
  }

  /// Picks up the train under the finger, if it can be moved.
  bool _liftTrain(Offset w) {
    final t = game.trainAt(w);
    if (t == null) return false;
    if (t.broken > 0) {
      game.notify('Kereta ini tertahan kecelakaan');
      return true; // still swallow the touch: don't start dragging the track under it
    }
    movingTrain = t..held = true;
    trainDir = t.dir;
    trainFinger = w;
    trainSpot = null;
    return true;
  }

  void _trainDragEnd() {
    final spot = trainSpot, dragged = trainFinger != null, moving = movingTrain;
    trainFinger = trainSpot = movingTrain = null;
    moving?.held = false;
    if (spot case (final l, final i, final at, _)) {
      final ok = moving == null
          ? game.addTrain(l, seg: i, dir: trainDir, at: at)
          : game.moveTrain(moving, l, seg: i, dir: trainDir, at: at) != null;
      if (ok) selected = l;
    } else if (dragged) {
      game.notify(moving == null ? 'Lepas keretanya di atas rel jalur' : 'Kereta dikembalikan ke tempatnya');
    }
  }

  (Offset, (Offset, double, Color)?, bool, String)? get _trainPreview {
    final f = trainFinger;
    if (f == null) return null;
    final moving = movingTrain;
    var fits = true;
    final snap = switch (trainSpot) {
      (final l, final i, final at, final heading) => () {
          fits = game.fitsTrain(l, i, trainDir, at, cars: moving?.cars ?? 0, except: moving);
          return (pointAlong(l.route(l.stops[i], l.stops[i + 1]), at).$1, heading + (trainDir == 1 ? 0 : pi), l.color);
        }(),
      null => null,
    };
    return (
      f,
      snap,
      fits && (moving != null || game.money >= Game.trainCost),
      !fits ? 'Terlalu dekat' : moving == null ? rp(Game.trainCost) : 'Pindah',
    );
  }

  Offset _toWorld(Offset p) => (p - origin) / scale;

  // ---- map input: one finger draws track, two fingers pinch-zoom and pan; on desktop the
  // wheel zooms at the cursor and a right/middle drag pans ----

  final _pointers = <int, Offset>{};
  int _buttons = kPrimaryButton;
  Offset _downAt = Offset.zero;
  bool _dragging = false; // a one-finger drag is under way
  bool _pinched = false; // this touch became a pinch: nothing is drawn until all fingers lift
  double _pinchDist = 1;

  Offset get _focal => _pointers.values.reduce((a, b) => a + b) / _pointers.length.toDouble();
  double get _spread {
    final ps = _pointers.values.toList();
    return ps.length < 2 ? 1 : max(1, (ps[0] - ps[1]).distance);
  }

  @override
  void pointerDown(PointerEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 1) {
      _buttons = e.buttons;
      _downAt = e.localPosition;
      _dragging = _pinched = false;
    } else if (_pointers.length == 2) {
      if (_dragging) _panEnd(); // a second finger drops the plan
      _dragging = false;
      pinching = _pinched = true;
      pinchZoom = zoom;
      pinchWorld = _toWorld(_focal);
      _pinchDist = _spread;
    }
  }

  @override
  void pointerMove(PointerEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    if (_buttons & (kSecondaryMouseButton | kMiddleMouseButton) != 0) {
      cam += e.localDelta;
      _clampCam();
      return;
    }
    if (pinching) {
      if (_pointers.length < 2) return;
      // keep the world point under the fingers fixed while zooming/panning
      zoom = (pinchZoom * _spread / _pinchDist).clamp(1.0, maxZoom);
      cam = _focal - pinchWorld * (fitScale * zoom) - fitOrigin;
      _clampCam();
      return;
    }
    if (_pinched) return;
    if (!_dragging) {
      final slop = e.kind == PointerDeviceKind.mouse ? 4.0 : kTouchSlop;
      if ((e.localPosition - _downAt).distance <= slop) return;
      _dragging = true;
      // from where the finger touched down: a quick swipe may already be past its station
      _panStart(_downAt);
    }
    _panUpdate(e.localPosition);
  }

  @override
  void pointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) pinching = false;
    if (_pointers.isNotEmpty) return;
    final primary = _buttons & kPrimaryButton != 0;
    if (_dragging) {
      _panEnd(commit: !_pinched);
    } else if (!_pinched && primary) {
      _tap(e.localPosition);
    }
    _dragging = false;
  }

  @override
  void pointerCancel(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) pinching = false;
    if (_pointers.isEmpty && _dragging) _panEnd();
    if (_pointers.isEmpty) _dragging = false;
  }

  void _tap(Offset screen) {
    final p = _toWorld(screen);
    if (newLineMode) return _tapPlan(p);
    final z = game.zoneAt(p);
    if (z != null) _confirmZone(z);
  }

  @override
  void scroll(Offset p, double dy) {
    final anchor = _toWorld(p);
    zoom = (zoom * pow(1.002, -dy)).clamp(1.0, maxZoom);
    cam = p - anchor * (fitScale * zoom) - fitOrigin;
    _clampCam();
  }

  /// Keeps the map covering the screen: no panning past its edges; zoom 1 = centred fit.
  void _clampCam() {
    final s = fitScale * zoom, o = fitOrigin + cam;
    // At zoom 1 the bounds are equal up to float rounding; min() keeps clamp's lower <= upper.
    final minX = min(view.width - fitOrigin.dx - worldSize.width * s, fitOrigin.dx);
    final minY = min(view.height - fitOrigin.dy - worldSize.height * s, fitOrigin.dy);
    cam = Offset(o.dx.clamp(minX, fitOrigin.dx), o.dy.clamp(minY, fitOrigin.dy)) - fitOrigin;
  }

  // "+" in the line list: planning a new line by tapping stations. The first station tapped
  // (or touched to start a drag) is its start; later taps add stations, tapping a planned one
  // drops it, and tapping the start again closes a loop. Bangun (or releasing a drag) builds.
  bool newLineMode = false;

  void _startNewLine() {
    _cancelPlan();
    newLineMode = true;
    selected = null;
  }

  void _cancelPlan() {
    newLineMode = false;
    dragStart = dragLine = finger = _holdAt = _inside = null;
    dragSeg = null;
    planned.clear();
  }

  void _tapPlan(Offset p) {
    final s = game.stationAt(p), anchor = dragStart;
    if (s == null) return;
    if (anchor == null) {
      dragStart = s;
    } else if (s == anchor) {
      if (planned.length < 2) return;
      _inside = s; // back at the start: a loop
      return _panEnd(commit: true);
    } else if (planned.contains(s)) {
      planned.remove(s);
    } else if (game.canLay(planned.lastOrNull ?? anchor, s)) {
      planned.add(s);
    }
    finger = (planned.lastOrNull ?? dragStart)!.pos;
  }

  void _panStart(Offset screen) {
    final p = _toWorld(screen);
    final s = game.stationAt(p);
    _inside = s; // touching down on a station counts as already being in it
    if (newLineMode) {
      dragStart ??= s; // always a new line: never extends or reroutes an existing one
      return;
    }
    if (s != null) {
      dragStart = s;
      final ends = game.lines.where((l) => !l.closing && !l.loop && (l.stops.first == s || l.stops.last == s));
      dragLine = ends.contains(selected) ? selected : ends.firstOrNull;
      dragHead = dragLine?.stops.first == s;
    } else if (_liftTrain(p)) {
      // a train picked up off its track: see [_trainDragAt]
    } else if (game.capAt(p, selected) case (final l, final head)) {
      dragLine = selected = l;
      dragHead = head;
      dragStart = head ? l.stops.first : l.stops.last;
    } else if (game.segmentAt(p, selected) case (final l, final i)) {
      dragLine = selected = l;
      dragSeg = i;
      dragStart = l.stops[i];
    }
  }

  // Dragging only plans; the plan is built on release ("done", see [_panEnd]). It grows from
  // dragStart: the start station, the extended end, or (rerouting) stops[dragSeg].
  //
  // Station events while the finger is down:
  //   in   – the finger enters a station's area: a new station joins the plan;
  //   out  – it leaves that area (cancels any hold);
  //   in again + stay [holdToDetach] – a planned station is dropped from the plan at once;
  //          a station of the existing track is armed ("Lepas") and detached on release.
  final planned = <Station>[];
  static const holdToDetach = Duration(milliseconds: 500);
  Duration _now = Duration.zero; // loop time; keeps running while paused
  Station? _inside; // station under the finger right now
  Station? _holdAt; // station being held to drop / detach
  Duration _holdSince = Duration.zero;
  bool _holdInPlan = false; // holding a planned station (vs. one on the existing track)
  double get _holdProgress =>
      _holdAt == null ? 0 : min(1, (_now - _holdSince).inMilliseconds / holdToDetach.inMilliseconds);

  /// Existing-track station that staying in [s] would detach, if any:
  /// - grabbed a piece of track and entered one of that segment's own stations → that station;
  /// - dragging a line's end: left the end station and came back into it → the end station.
  Station? _detachTargetAt(Station s) {
    final l = dragLine;
    if (l == null || planned.isNotEmpty) return null;
    if (dragSeg case final i?) return s == l.stops[i] || s == l.stops[i + 1] ? s : null;
    return s == dragStart ? s : null;
  }

  void _hold(Station s, {required bool inPlan}) {
    _holdAt = s;
    _holdSince = _now;
    _holdInPlan = inPlan;
  }

  void _panUpdate(Offset screen) {
    if (movingTrain != null) {
      final w = _toWorld(screen);
      _trainDragAt(w, w - (trainFinger ?? w));
      return;
    }
    final anchor = dragStart;
    if (anchor == null) return;
    finger = _toWorld(screen);
    final s = game.stationAt(finger!);
    if (s == _inside) return; // no in/out event; a running hold is timed by the loop
    _inside = s; // out of the previous station (if any) ...
    _holdAt = null;
    if (s == null) return; // ... and in to s:
    if (_detachTargetAt(s) case final target?) {
      _hold(target, inPlan: false);
      game.notify('Diam sebentar untuk melepas stasiun dari jalur');
      return;
    }
    if (planned.contains(s)) {
      _hold(s, inPlan: true); // re-entered a planned station: stay to drop it
      return;
    }
    final line = dragLine;
    if (s == anchor || (line?.stops.contains(s) ?? false)) return;
    final tail = planned.isEmpty ? anchor : planned.last;
    final i = dragSeg;
    final ok = i == null ? game.canLay(tail, s) : game.canLay(tail, s) && game.canLay(s, line!.stops[i + 1]);
    if (ok) planned.add(s);
  }

  /// Releasing on this station closes the plan into a loop: the start station of a new line,
  /// or the far end of the line being extended, with 3+ stations in all.
  Station? get _loopTarget {
    final a = dragStart, l = dragLine;
    if (a == null || dragSeg != null || _inside == null) return null;
    final target = l == null ? a : (dragHead ? l.stops.last : l.stops.first);
    return _inside == target && (l?.stops.length ?? 1) + planned.length >= 3 ? target : null;
  }

  /// Grabbed a piece of track and pulled it out onto open ground (no new stations): releasing
  /// bends the segment through the finger, exactly as the plan shows. Let go back on the
  /// plain route, a bent segment is straightened again. (via,) with via null = straighten.
  (Offset?,)? get _reshape {
    final l = dragLine, i = dragSeg, f = finger;
    if (l == null || i == null || f == null || planned.isNotEmpty || _inside != null) return null;
    final a = l.stops[i], b = l.stops[i + 1];
    if (distToPolyline(f, l.route(a, b)) < 20) return null; // still on the track: no change
    if (l.bends.containsKey(MetroLine.key(a, b)) && distToPolyline(f, pathBetween(a.pos, b.pos)) < 20) return (null,);
    return (f,);
  }

  /// Release builds the plan, if affordable; [commit] false just drops it (e.g. a pinch began).
  void _panEnd({bool commit = false}) {
    if (movingTrain case final t?) {
      if (!commit) {
        t.held = false;
        movingTrain = trainFinger = trainSpot = null;
      } else {
        _trainDragEnd();
      }
      return;
    }
    if (newLineMode && !commit) {
      // e.g. a pinch began: keep the tapped plan, just park its end on the last station
      finger = (planned.lastOrNull ?? dragStart)?.pos;
      _inside = null;
      return;
    }
    if (newLineMode && (planned.isNotEmpty || _loopTarget != null)) newLineMode = false;
    final anchor = dragStart, line = dragLine, seg = dragSeg, plan = [...planned], loopTo = _loopTarget;
    final detachAt = !_holdInPlan && _holdProgress >= 1 ? _holdAt : null;
    final reshape = _reshape;
    dragStart = dragLine = finger = _holdAt = _inside = null;
    dragSeg = null;
    planned.clear();
    if (commit && line != null && detachAt != null) {
      game.detach(line, line.stops.indexOf(detachAt));
      return;
    }
    if (commit && line != null && seg != null && reshape != null) {
      game.reshape(line, seg, reshape.$1);
      return;
    }
    if (!commit || anchor == null || (plan.isEmpty && loopTo == null)) return;
    final cost = game.planCost(anchor, plan, line: line, seg: seg, loopTo: loopTo);
    if (cost > game.money) {
      game.notify('Uang kurang: rencana ini butuh ${rp(cost)}');
      return;
    }
    if (line == null) {
      final l = game.createLine(anchor, plan.first);
      if (l == null) return;
      selected = l;
      for (final s in plan.skip(1)) {
        game.extend(l, s, atHead: false);
      }
      if (loopTo != null) game.closeLoop(l);
    } else if (seg != null) {
      game.reroute(line, seg, plan);
    } else {
      for (final s in plan) {
        game.extend(line, s, atHead: dragHead);
      }
      if (loopTo != null) game.closeLoop(line);
    }
  }

  /// Planned route (anchor → planned stops → finger, and back to the far end when
  /// rerouting a segment), its colour and cost label.
  (List<Offset>, Offset, Color, String, bool)? get _dragPreview {
    final f = finger, anchor = dragStart;
    if (anchor == null || f == null) return null;
    final l = dragLine, seg = dragSeg;
    final chain = [anchor.pos, for (final s in planned) s.pos, f, if (seg != null) l!.stops[seg + 1].pos];
    final color = l?.color ?? game.nextColor ?? Colors.grey;
    if (_reshape case (final via,)) {
      final (cost, _, _) = game.reshapeCost(l!, seg!, via);
      return (chain, f, color, '↝ ${rp(cost)}', cost <= game.money);
    }
    final loopTo = _loopTarget;
    if (planned.isEmpty && loopTo == null) return (chain, f, color, '', true);
    final cost = game.planCost(anchor, planned, line: l, seg: seg, loopTo: loopTo);
    return (chain, f, color, '${loopTo != null ? '⟳ ' : ''}${rp(cost)}', cost <= game.money);
  }

  double _resumeSpeed = 1;

  // Developer FPS meter: on by default outside release builds; F toggles it anywhere.
  bool showFps = Settings.showFps;
  double _frameMs = 0; // smoothed time between frames

  // The same switches as in Pengaturan (kept on the device).
  void _toggleMusic() {
    Settings.music = !Settings.music;
    Settings.save();
  }

  void _toggleSfx() {
    Settings.sfx = !Settings.sfx;
    Settings.save();
  }

  /// Space: pause, or resume at the speed you had before pausing.
  void _togglePause() {
    if (speed == 0) {
      speed = _resumeSpeed;
    } else {
      _resumeSpeed = speed;
      speed = 0;
    }
  }

  @override
  bool key(LogicalKeyboardKey k) {
    if (k == LogicalKeyboardKey.space) {
      _togglePause();
    } else if (k == LogicalKeyboardKey.keyF) {
      showFps = !showFps;
    } else if (k == LogicalKeyboardKey.escape) {
      _cancelPlan();
    } else if (k == LogicalKeyboardKey.keyM) {
      _toggleSfx();
    } else if (k == LogicalKeyboardKey.keyN) {
      _toggleMusic();
    } else {
      return false;
    }
    return true;
  }

  @override
  bool back() {
    if (!newLineMode && dragStart == null) return false;
    _cancelPlan();
    return true;
  }

  /// Any touch elsewhere folds up the fare and the price labels.
  @override
  void anyDown(Offset p, UiArea? on) {
    final id = on?.id ?? '';
    if (fareOpen && !id.startsWith('fare')) fareOpen = false;
    if (tokenInfo != null && !id.endsWith('Token')) tokenInfo = null;
  }

  // ---- drawing ----

  @override
  void render(Canvas canvas, Size size) {
    view = size;
    fitScale = min(size.width / worldSize.width, size.height / worldSize.height);
    fitOrigin = Offset((size.width - worldSize.width * fitScale) / 2, (size.height - worldSize.height * fitScale) / 2);
    _clampCam(); // also re-fits after a rotation
    scale = fitScale * zoom;
    origin = fitOrigin + cam;
    canvas.save();
    _painter.paint(canvas, size);
    canvas.restore();

    final pad = ui.pad;
    _stats(Offset(pad.left + 16, pad.top + 12));
    if (newLineMode) {
      _newLineBanner(size.width / 2, pad.top + 12);
    } else {
      _goals(size.width / 2, pad.top + 12);
    }
    _topBar(size.width - pad.right - 12, pad.top + 12);
    _speedButtons(size.width - pad.right - 34, pad.top + 76);
    _linePalette(size.width - pad.right - 34, size.height / 2, size.height - pad.bottom - 12);
    if (game.lines.any((l) => !l.closing)) _buyTokens(pad.left + 16, size.height / 2);
    _fare(Offset(pad.left + 16, size.height - pad.bottom - 12));
    if (game.lines.isEmpty && !newLineMode) {
      ui.text('Tarik jari dari satu stasiun ke stasiun lain untuk membuka jalur pertama (gratis)',
          Offset(size.width / 2, size.height * .075 + pad.top),
          size: 15, weight: FontWeight.w500, color: Colors.black54, anchor: Alignment.topCenter,
          maxWidth: size.width - 320, align: TextAlign.center);
    }
    if (game.messageTime > 0 && game.message != null) _toast(game.message!, size);
    if (showFps && _frameMs > 0) _fpsMeter(Offset(size.width - pad.right - 12, size.height - pad.bottom - 12));
    if (popup case final p?) _eventModal(p, size);
    if (game.gameOver != null || game.finished) _endCard(size);
  }

  /// The city's goals (money earned, stations connected, riders delivered; no time limit)
  /// as three meters at the top centre. Tapped open, they show the numbers and the running
  /// costs underneath.
  bool statsOpen = false;
  static const _goalIcons = [Icons.payments_outlined, Icons.hub_outlined, Icons.people_alt_outlined];

  void _stats(Offset at) {
    var y = at.dy;
    final money = game.money;
    y = ui.text(rp(money), Offset(at.dx, y), size: 28, weight: FontWeight.w900, color: money < 0 ? red : ink).bottom;
    y = ui.text('${monthNames[game.month % 12]} · Tahun ${game.month ~/ 12 + 1}', Offset(at.dx, y)).bottom;
    if (game.endless) {
      y = ui.text('∞ Main terus', Offset(at.dx, y), color: green, weight: FontWeight.w800).bottom;
    }
    if (game.festival != null) {
      y = ui.text(
              game.festivalOpen
                  ? '🎉 ${game.festival}: ${game.festivalLeft.ceil()} dtk lagi'
                  : '🎉 ${game.festival} tutup · ${game.festivalRiders} 🚶',
              Offset(at.dx, y),
              color: festivalColor,
              weight: FontWeight.w800)
          .bottom;
    }
    if (game.stations.where((s) => s.upset > 0.05).length case final n when n > 0) {
      y = ui.text('Warga kesal di $n stasiun (tanda 😠)', Offset(at.dx, y), color: red, weight: FontWeight.w800).bottom;
    }
    if (!game.endless) _angerMeter(Offset(at.dx, y + 4));
  }

  /// Riders who walked off lately: full = game over. Drains after [Game.angerHold] s of calm.
  void _angerMeter(Offset at) {
    final f = min(1.0, game.anger / Game.angerLimit);
    final calming = game.anger > 0 && game.calmFor > Game.angerHold;
    ui.text('😠', Offset(at.dx, at.dy + 10), size: 16, anchor: Alignment.centerLeft);
    ui.bar(Rect.fromLTWH(at.dx + 26, at.dy + 6, 120, 8), f, Color.lerp(const Color(0xFFE8B83A), red, f)!);
    ui.text('${game.anger.ceil()}/${Game.angerLimit.round()}${calming ? ' ↓' : ''}', Offset(at.dx + 154, at.dy + 10),
        size: 12, color: f > .6 ? red : ink, anchor: Alignment.centerLeft);
    ui.area('anger', Rect.fromLTWH(at.dx, at.dy, 190, 20));
  }

  void _goals(double cx, double top) {
    const itemW = 22 + 6 + 90.0, gap = 16.0;
    final w = 3 * itemW + 2 * gap + 6 + 20;
    var x = cx - w / 2;
    final row = Rect.fromLTWH(x, top, w, 24);
    for (final (i, (have, need)) in game.goals.indexed) {
      final done = have >= need;
      ui.icon(done ? Icons.check_circle : _goalIcons[i], Offset(x + 11, top + 12), size: 22, color: done ? green : ink);
      ui.bar(Rect.fromLTWH(x + 28, top + 8, 90, 8), min(1, have / need), const Color(0xFF43A047));
      x += itemW + gap;
    }
    ui.icon(statsOpen ? Icons.expand_less : Icons.expand_more, Offset(row.right - 10, top + 12), size: 20);
    ui.area('stats', row.inflate(6), onTap: () => statsOpen = !statsOpen);
    if (!statsOpen) return;
    // the numbers: icons with rounded values, then the running costs
    final lines = <(IconData?, String, Color)>[
      for (final (i, (have, need)) in game.goals.indexed)
        (have >= need ? Icons.check_circle : _goalIcons[i], '${short(have)} / ${short(need)}', have >= need ? green : ink),
      (Icons.directions_walk, short(game.lost), ink),
      (Icons.trending_up, '+${short(game.lastIncome)}  −${short(game.lastCost)}', ink),
      (Icons.build_outlined, '${short(game.monthlyCost)}/bulan', ink),
      (null, '${game.trainCount} kereta × ${short(Game.trainUpkeep)} · ${game.lines.length} jalur × ${short(Game.lineUpkeep)}', Colors.black54),
    ];
    const lh = 22.0;
    final panel = Rect.fromCenter(center: Offset(cx, top + 32 + 10 + lines.length * lh / 2), width: 260, height: lines.length * lh + 20);
    ui.box(panel, fill: Colors.white.withValues(alpha: .95), radius: 12);
    var y = panel.top + 10;
    for (final (icon, label, color) in lines) {
      if (icon != null) ui.icon(icon, Offset(panel.left + 24, y + lh / 2), size: 18, color: color);
      ui.text(label, Offset(panel.left + (icon == null ? 16 : 42), y + lh / 2),
          color: color, anchor: Alignment.centerLeft, size: icon == null ? 11 : 13, maxWidth: panel.width - 50, maxLines: 1);
      y += lh;
    }
    ui.area('statsPanel', panel, onTap: () => statsOpen = false);
  }

  /// An icon button: [icon] at [c]; faded and inactive when [onTap] is null.
  void _iconButton(String id, IconData icon, Offset c, VoidCallback? onTap, {double size = 26}) {
    ui.icon(icon, c, size: size, color: onTap == null ? ink.withValues(alpha: .3) : ink);
    if (onTap != null) ui.area(id, Rect.fromCircle(center: c, radius: 22), onTap: onTap);
  }

  void _topBar(double right, double top) {
    final cy = top + 20;
    final name = ui.text(city.name, Offset(right, cy), size: 18, weight: FontWeight.w800, anchor: Alignment.centerRight);
    var x = name.left - 32;
    ui.back(Offset(x, cy), app.pop);
    x -= 50;
    _iconButton('sfx', Settings.sfx ? Icons.volume_up : Icons.volume_off, Offset(x, cy), _toggleSfx);
    x -= 44;
    _iconButton('music', Settings.music ? Icons.music_note : Icons.music_off, Offset(x, cy), _toggleMusic);
    if (zoom > 1) {
      x -= 44;
      _iconButton('fit', Icons.zoom_out_map, Offset(x, cy), () {
        zoom = 1;
        cam = Offset.zero;
      });
    }
  }

  /// Pause / play / fast, stacked vertically. The current mode can't be pressed again,
  /// so it is drawn semi-transparent.
  void _speedButtons(double cx, double top) {
    for (final (i, (s, icon)) in [(0.0, Icons.pause), (1.0, Icons.play_arrow), (2.0, Icons.fast_forward)].indexed) {
      _iconButton('speed$i', icon, Offset(cx, top + i * 46), speed == s ? null : () => speed = s, size: 30);
    }
  }

  /// Lines in the order they were opened (train count inside), then the "+" for the next
  /// one, then small dots for colours not unlocked yet: the list grows downwards, shrinking
  /// to fit if it runs out of room.
  void _linePalette(double cx, double top, double bottom) {
    final next = game.nextColor;
    final used = [for (final l in game.lines) l.color];
    final locked = lineColors.where((c) => !used.contains(c) && c != next).length;
    final full = used.length * 48 + (next == null ? 0 : 58) + locked * 22.0;
    final k = min(1.0, (bottom - top) / max(1, full));
    var y = top;
    for (final color in used) {
      final line = game.lines.firstWhere((l) => l.color == color);
      final c = Offset(cx, y + 24 * k);
      if (line.closing) {
        // winding down: faded, not selectable, how many trains are still out
        ui.circle(c, 20 * k, fill: color.withValues(alpha: .3));
        ui.text('⏳${line.trains.length}', c, size: 11 * k, weight: FontWeight.w800, anchor: Alignment.center);
      } else {
        ui.circle(c, 20 * k, fill: color);
        ui.icon(Icons.train, c - Offset(7 * k, 0), size: 13 * k, color: Colors.white);
        ui.text('${line.trains.length}', c + Offset(6 * k, 0),
            size: 13 * k, weight: FontWeight.w900, color: Colors.white, anchor: Alignment.center);
        ui.area('line:${game.lines.indexOf(line)}', Rect.fromCircle(center: c, radius: 22 * k),
            onTap: () => selected = line, onLongPress: () => _confirmDelete(line));
      }
      y += 48 * k;
    }
    if (next != null) {
      final c = Offset(cx, y + 21 * k);
      ui.circle(c, 17 * k, fill: Colors.white.withValues(alpha: 0), border: next, borderWidth: 3 * k);
      ui.icon(Icons.add, c, size: 20 * k, color: next);
      ui.text(rp(game.nextLineCost), Offset(cx, c.dy + 19 * k), size: 10 * k, weight: FontWeight.w700, anchor: Alignment.topCenter);
      ui.area('newLine', Rect.fromCircle(center: c, radius: 22 * k), onTap: _startNewLine);
      y += 58 * k;
    }
    for (var i = 0; i < locked; i++) {
      ui.circle(Offset(cx, y + 11 * k), 7 * k, fill: const Color(0x1F000000));
      y += 22 * k;
    }
  }

  /// Event pop-up: pauses the city until the player acknowledges it (see [_eventModal]).
  (String, String, String)? popup;
  double _popupResume = 1;

  void _showPopup((String, String, String) event) {
    popup = event;
    _popupResume = speed;
    speed = 0;
  }

  void _closePopup() {
    popup = null;
    speed = _popupResume;
  }

  /// The event pop-up over the map: its picture (`assets/events/<name>.png`, the emoji until
  /// there is one), title and text.
  void _eventModal((String, String, String) event, Size size) {
    final (icon, title, body) = event;
    ui.barrier();
    final w = min(440.0, size.width - 48), imgH = w * 9 / 16;
    final titleH = ui.measure(title, size: 20, weight: FontWeight.w900, maxWidth: w - 40).height;
    final bodyH = ui.measure(body, size: 14, weight: FontWeight.w500, maxWidth: w - 40).height;
    final h = imgH + 16 + titleH + 8 + bodyH + 16 + 44 + 18;
    final k = min(1.0, (size.height - 24) / h); // squeeze the picture on short screens
    final ih = imgH * k, card = Rect.fromCenter(center: size.center(Offset.zero), width: w, height: h - imgH + ih);
    ui.box(card, fill: paper, radius: 20, border: ink, borderWidth: 3);
    ui.area('eventModal', card, onTap: () {});
    final img = Rect.fromLTWH(card.left + 3, card.top + 3, w - 6, ih - 3);
    if (ui.image('assets/events/${eventImageName(title)}.png') case final pic?) {
      ui.cover(pic, img, radius: 17);
    } else {
      ui.canvas.drawRRect(
          RRect.fromRectAndCorners(img, topLeft: const Radius.circular(17), topRight: const Radius.circular(17)),
          Paint()..color = const Color(0xFFE9E6DF));
      ui.text(icon, img.center, size: 64 * k, anchor: Alignment.center);
    }
    var y = card.top + ih + 16;
    ui.text(title, Offset(card.center.dx, y),
        size: 20, weight: FontWeight.w900, anchor: Alignment.topCenter, maxWidth: w - 40, align: TextAlign.center);
    y += titleH + 8;
    ui.text(body, Offset(card.center.dx, y),
        size: 14, weight: FontWeight.w500, anchor: Alignment.topCenter, maxWidth: w - 40, align: TextAlign.center);
    ui.button('oke', Rect.fromCenter(center: Offset(card.center.dx, card.bottom - 18 - 22), width: 120, height: 44), 'Oke',
        primary: true, onTap: _closePopup);
  }

  Future<void> _confirmZone(Zone z) async {
    final a = await app.ask(z.name, 'Bayar izin ${rp(z.price)}? Uangmu ${rp(game.money)}.',
        [('Nanti', false), ('Bayar ${rp(z.price)}', true)]);
    if (a == 1) game.buyZone(z);
  }

  Future<void> _confirmDelete(MetroLine line) async {
    final prev = speed;
    speed = 0;
    final a = await app.ask('Tutup jalur ini?', 'Biaya pembangunan tidak dikembalikan.', [('Batal', false), ('Tutup jalur', true)]);
    if (a == 1) {
      game.closeLine(line);
      if (selected == line) selected = null;
    }
    speed = prev;
  }

  /// The fare: just the price until tapped, then − / + and what's fair here. Folds itself
  /// up again when the mouse leaves it or anything else is touched.
  bool fareOpen = false;
  bool _fareHovered = false;

  void _fare(Offset bottomLeft) {
    const h = 40.0;
    Rect chip;
    if (!fareOpen) {
      final t = ui.measure(rp(game.fare), size: 14, weight: FontWeight.w800);
      chip = Rect.fromLTWH(bottomLeft.dx, bottomLeft.dy - h, 24 + 18 + 6 + t.width + 12, h);
      ui.box(chip);
      ui.icon(Icons.confirmation_number_outlined, Offset(chip.left + 21, chip.center.dy), size: 18);
      ui.text(rp(game.fare), Offset(chip.left + 36, chip.center.dy), size: 14, weight: FontWeight.w800, anchor: Alignment.centerLeft);
      ui.area('fare', chip, onTap: () => fareOpen = true);
    } else {
      final hint = 'wajar ${rp(city.normalFare)} · sabar ${game.patience.round()} dtk';
      final hw = ui.measure(hint, size: 11, weight: FontWeight.w500).width;
      final fw = max(56.0, ui.measure(rp(game.fare), size: 14, weight: FontWeight.w800).width);
      chip = Rect.fromLTWH(bottomLeft.dx, bottomLeft.dy - h, 16 + 40 + 36 + fw + 36 + 8 + hw + 40, h);
      ui.box(chip);
      var x = chip.left + 16;
      x = ui.text('Tarif', Offset(x, chip.center.dy), size: 14, anchor: Alignment.centerLeft).right + 4;
      _iconButton('fare-', Icons.remove, Offset(x + 16, chip.center.dy),
          () => game.fare = max(Game.fareStep, game.fare - Game.fareStep), size: 18);
      x += 36;
      ui.text(rp(game.fare), Offset(x + fw / 2, chip.center.dy), size: 14, weight: FontWeight.w800, anchor: Alignment.center);
      x += fw;
      _iconButton('fare+', Icons.add, Offset(x + 16, chip.center.dy),
          () => game.fare = min(city.normalFare * 4, game.fare + Game.fareStep), size: 18);
      x += 40;
      ui.text(hint, Offset(x, chip.center.dy), size: 11, weight: FontWeight.w500, color: Colors.black54, anchor: Alignment.centerLeft);
      _iconButton('fareClose', Icons.close, Offset(chip.right - 22, chip.center.dy), () => fareOpen = false, size: 18);
      ui.area('fareBar', chip);
    }
    final over = ui.hovered(chip);
    if (_fareHovered && !over) fareOpen = false; // the mouse left it
    _fareHovered = over;
  }

  /// What to do next while planning a new line from "+", with its price, Bangun and Batal.
  void _newLineBanner(double cx, double top) {
    final anchor = dragStart;
    final cost = anchor == null || planned.isEmpty ? null : game.planCost(anchor, planned);
    final label = anchor == null
        ? 'Ketuk stasiun awal jalur baru'
        : planned.isEmpty
            ? 'Ketuk stasiun berikutnya'
            : '${planned.length + 1} stasiun · ${rp(cost!)}';
    final tw = ui.measure(label, size: 14, weight: FontWeight.w700).width;
    const bw = 92.0, h = 48.0;
    final w = 16 + 14 + 10 + tw + 12 + (cost == null ? 0 : bw + 8) + bw + 8;
    final chip = Rect.fromLTWH(cx - w / 2, top, w, h);
    ui.box(chip);
    ui.area('banner', chip);
    ui.circle(Offset(chip.left + 23, chip.center.dy), 7, fill: game.nextColor ?? Colors.grey);
    ui.text(label, Offset(chip.left + 40, chip.center.dy),
        size: 14, weight: FontWeight.w700, color: cost != null && cost > game.money ? red : ink, anchor: Alignment.centerLeft);
    var x = chip.left + 40 + tw + 12;
    if (cost != null) {
      ui.button('buildPlan', Rect.fromLTWH(x, chip.top + 6, bw, h - 12), 'Bangun',
          primary: true, size: 14, onTap: () => _panEnd(commit: true));
      x += bw + 8;
    }
    ui.button('cancelPlan', Rect.fromLTWH(x, chip.top + 6, bw, h - 12), 'Batal', size: 14, onTap: _cancelPlan);
  }

  /// Left rail from mid-height down: carriages (dragged onto a train or a track) and new
  /// trains (dragged onto a track; sliding along it picks their direction). Just icons; the
  /// price shows beside one while it is hovered or tapped.
  String? tokenInfo;

  void _buyTokens(double left, double top) {
    var y = top;
    if (game.lines.any((l) => !l.closing && l.trains.isNotEmpty)) {
      _dragToken('carToken', Icons.add_box_outlined, Game.carCost, Offset(left + 22, y + 22),
          dragging: carFinger != null,
          onMove: (p, _) => _carDragMove(p),
          onEnd: _carDragEnd,
          onCancel: () => carFinger = carTarget = null);
      y += 52;
    }
    _dragToken('trainToken', Icons.train, Game.trainCost, Offset(left + 22, y + 22),
        dragging: trainFinger != null,
        onMove: (p, d) => _trainDragAt(_toWorld(p), d),
        onEnd: _trainDragEnd,
        onCancel: () => trainFinger = trainSpot = null);
  }

  /// Something to buy by dragging it onto the map. Faded and not draggable while it costs
  /// more than we have; it comes back as soon as the money is there. A drag already under
  /// way is never cut off.
  void _dragToken(String id, IconData icon, int cost, Offset c,
      {required bool dragging,
      required void Function(Offset at, Offset delta) onMove,
      required VoidCallback onEnd,
      required VoidCallback onCancel}) {
    final ok = dragging || game.money >= cost;
    final r = Rect.fromCircle(center: c, radius: 22);
    ui.faded(ok ? 1 : .4, () {
      ui.circle(c, 22, shadow: true);
      ui.icon(icon, c, size: 24);
    });
    if (tokenInfo == id || (ui.hovered(r) && !dragging)) {
      final label = rp(cost), t = ui.measure(label, size: 14, weight: FontWeight.w800);
      final chip = Rect.fromLTWH(r.right + 8, c.dy - 17, t.width + 24, 34);
      ui.box(chip);
      ui.text(label, chip.center, size: 14, weight: FontWeight.w800, color: game.money >= cost ? ink : red, anchor: Alignment.center);
    }
    ui.area(id, r,
        onTap: () => tokenInfo = tokenInfo == id ? null : id,
        onPanStart: ok
            ? (p) {
                tokenInfo = null;
                onMove(p, Offset.zero);
              }
            : null,
        onPanUpdate: ok ? onMove : null,
        onPanEnd: ok ? onEnd : null,
        onPanCancel: ok ? onCancel : null);
  }

  void _toast(String text, Size size) {
    final t = ui.measure(text, size: 14, weight: FontWeight.w500, maxWidth: size.width - 80);
    final r = Rect.fromCenter(center: Offset(size.width / 2, size.height * .86), width: t.width + 32, height: t.height + 16);
    ui.box(r, fill: ink, radius: 20, shadow: false);
    ui.text(text, r.center,
        size: 14, weight: FontWeight.w500, color: Colors.white, anchor: Alignment.center, maxWidth: size.width - 80, align: TextAlign.center);
  }

  void _fpsMeter(Offset bottomRight) {
    final fps = 1000 / _frameMs;
    final label = '${fps.round()} fps · ${_frameMs.toStringAsFixed(1).replaceAll('.', ',')} ms';
    final t = ui.measure(label, size: 12, weight: FontWeight.w700);
    final r = Rect.fromLTRB(bottomRight.dx - t.width - 16, bottomRight.dy - t.height - 6, bottomRight.dx, bottomRight.dy);
    ui.box(r, fill: Colors.black54, radius: 6, shadow: false);
    ui.text(label, r.center, size: 12, weight: FontWeight.w700, color: fps < 50 ? const Color(0xFFEF9A9A) : Colors.white, anchor: Alignment.center);
  }

  /// Won or lost: the result, then carry on / next city, or back / play again.
  void _endCard(Size size) {
    ui.barrier();
    final title = game.gameOver ?? '${city.name} terhubung! 🎉';
    final summary = '${game.month + 1} bulan · ${game.delivered} penumpang · ${rp(game.earned)} pendapatan';
    final i = cities.indexOf(city), last = i + 1 >= cities.length;
    final buttons = game.gameOver == null
        ? [
            ('endless', 'Main terus di ${city.name}', Icons.all_inclusive, false, () {
              game.endless = true;
              _save();
            }),
            ('nextCity', last ? 'Selesai' : 'Lanjut ke ${cities[i + 1].name}', null, true, () {
              if (last) return app.pop();
              app.replace(CityScene(cities[i + 1]));
            }),
          ]
        : [
            ('backToPicker', 'Kembali', null, false, app.pop),
            ('again', 'Main lagi', null, true, () {
              game = Game(city);
              selected = null;
              speed = 1;
            }),
          ];
    final widths = [for (final b in buttons) ui.measure(b.$2, size: 15, weight: FontWeight.w800).width + (b.$3 == null ? 36 : 60)];
    final bw = widths.reduce((a, b) => a + b) + 10;
    final w = max(bw, ui.measure(title, size: 20, weight: FontWeight.w800).width) + 48;
    final card = Rect.fromCenter(center: size.center(Offset.zero), width: min(w, size.width - 32), height: 150);
    ui.box(card, fill: paper, radius: 20, border: ink, borderWidth: 3);
    ui.area('endCard', card, onTap: () {});
    ui.text(title, Offset(card.center.dx, card.top + 24),
        size: 20, weight: FontWeight.w800, anchor: Alignment.topCenter, maxWidth: card.width - 32, maxLines: 1);
    ui.text(summary, Offset(card.center.dx, card.top + 60), weight: FontWeight.w500, anchor: Alignment.topCenter);
    var x = card.center.dx - bw / 2;
    for (final (j, (id, label, icon, primary, onTap)) in buttons.indexed) {
      ui.button(id, Rect.fromLTWH(x, card.bottom - 24 - 42, widths[j], 42), label, icon: icon, primary: primary, onTap: onTap);
      x += widths[j] + 10;
    }
  }
}
