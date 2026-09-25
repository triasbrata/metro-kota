import 'dart:async';
import 'dart:math';

import 'package:flame/game.dart' as flame;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'painter.dart' show ink;
import 'ui.dart';

/// One screen of the game (menu, city picker, settings, a city). Everything it shows is drawn
/// on the game canvas in [render] through [ui]; pointer events that hit none of its UI areas
/// come to the pointer methods.
abstract class Scene {
  late App app;
  Ui get ui => app.ui;

  void enter() {} // pushed onto the stack
  void resume() {} // on top again after the scene above it closed
  void exit() {} // taken off the stack
  void update(double dt) {}
  void render(Canvas canvas, Size size);

  void pointerDown(PointerEvent e) {}
  void pointerMove(PointerEvent e) {}
  void pointerUp(PointerEvent e) {}
  void pointerCancel(PointerEvent e) {}

  /// Any touch at all, before it goes anywhere ([on]: the UI area it landed on, if any).
  void anyDown(Offset p, UiArea? on) {}
  void scroll(Offset p, double dy) {}
  bool key(LogicalKeyboardKey k) => false;

  /// The back button / gesture: true if the scene dealt with it itself.
  bool back() => false;
}

/// The whole app: one game canvas. The only widgets are this invisible root, the input
/// listener and Flame's GameWidget.
class MetroKota extends StatefulWidget {
  const MetroKota({super.key, required this.home});
  final Scene Function() home;
  @override
  State<MetroKota> createState() => App();
}

class _Loop extends flame.Game {
  _Loop(this.app);
  final App app;

  @override
  Color backgroundColor() => const Color(0xFFF4F2EE);

  @override
  void update(double dt) => app._update(dt);

  @override
  void render(Canvas canvas) => app._render(canvas, Size(size.x, size.y));
}

/// A question drawn over the current scene: pressing a button closes it with that answer.
class _Dialog {
  _Dialog(this.title, this.body, this.buttons, this.done);
  final String title;
  final String? body;
  final List<(String label, bool primary)> buttons;
  final Completer<int?> done;
}

class _Press {
  _Press(this.pointer, this.area, this.down);
  final int pointer;
  final UiArea area;
  final Offset down;
  bool dragging = false, toScene = false, longFired = false;
  double held = 0;
}

class App extends State<MetroKota> with WidgetsBindingObserver {
  final ui = Ui();
  final stack = <Scene>[];
  late final _loop = _Loop(this);
  Scene get top => stack.last;

  void push(Scene s) {
    s.app = this;
    stack.add(s);
    s.enter();
  }

  void pop() {
    if (stack.length <= 1) return;
    stack.removeLast().exit();
    top.resume();
  }

  void replace(Scene s) {
    stack.removeLast().exit();
    push(s);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_key);
    push(widget.home());
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_key);
    WidgetsBinding.instance.removeObserver(this);
    while (stack.isNotEmpty) {
      stack.removeLast().exit();
    }
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    if (_dialog != null) {
      _answer(null);
      return true;
    }
    if (top.back()) return true;
    if (stack.length <= 1) return false;
    pop();
    return true;
  }

  bool _key(KeyEvent e) {
    if (e is! KeyDownEvent || stack.isEmpty) return false;
    if (_dialog != null && e.logicalKey == LogicalKeyboardKey.escape) {
      _answer(null);
      return true;
    }
    return top.key(e.logicalKey);
  }

  // ---- dialogs and toasts ----

  _Dialog? _dialog;

  /// Asks a question over the current scene; the index of the button pressed, or null if
  /// dismissed (tap outside, Esc, back).
  Future<int?> ask(String title, String? body, List<(String, bool primary)> buttons) {
    _dialog?.done.complete(null);
    final d = _Dialog(title, body, buttons, Completer());
    _dialog = d;
    return d.done.future;
  }

  bool get dialogOpen => _dialog != null;

  void _answer(int? i) {
    final d = _dialog;
    _dialog = null;
    d?.done.complete(i);
  }

  String? _toast;
  double _toastLeft = 0;

  void toast(String text) {
    _toast = text;
    _toastLeft = 2.5;
  }

  // ---- the loop ----

  void _update(double dt) {
    if (_toastLeft > 0) _toastLeft -= dt;
    if (_press case final p? when !p.dragging && !p.toScene && !p.longFired && p.area.onLongPress != null) {
      if ((p.held += dt) >= .5) {
        p.longFired = true;
        p.area.onLongPress!();
      }
    }
    if (stack.isNotEmpty) top.update(dt);
  }

  void _render(Canvas canvas, Size size) {
    if (stack.isEmpty) return;
    ui.begin(canvas, size);
    top.render(canvas, size);
    if (_dialog case final d?) _drawDialog(d);
    if (_toastLeft > 0 && _toast != null) {
      final t = ui.measure(_toast!, size: 14, maxWidth: size.width - 64);
      final r = Rect.fromCenter(
          center: Offset(size.width / 2, size.height - ui.pad.bottom - 48), width: t.width + 32, height: t.height + 16);
      ui.box(r, fill: ink, radius: 20, shadow: false);
      ui.text(_toast!, r.center,
          size: 14, color: Colors.white, anchor: Alignment.center, maxWidth: size.width - 64, align: TextAlign.center);
    }
    ui.end();
  }

  void _drawDialog(_Dialog d) {
    ui.barrier(onTap: () => _answer(null));
    final size = ui.size, w = min(420.0, size.width - 48);
    final titleH = ui.measure(d.title, size: 19, weight: FontWeight.w900, maxWidth: w - 48).height;
    final bodyH = d.body == null ? 0.0 : ui.measure(d.body!, size: 14, weight: FontWeight.w500, maxWidth: w - 48).height + 10;
    final h = 24 + titleH + bodyH + 20 + 42 + 22;
    final card = Rect.fromCenter(center: size.center(Offset.zero), width: w, height: h);
    ui.box(card, fill: paper, radius: 20, border: ink, borderWidth: 3);
    ui.area('dialog', card, onTap: () {}); // taps on the card don't dismiss it
    var y = card.top + 24;
    ui.text(d.title, Offset(card.left + 24, y), size: 19, weight: FontWeight.w900, maxWidth: w - 48);
    y += titleH + 10;
    if (d.body case final body?) {
      ui.text(body, Offset(card.left + 24, y), size: 14, weight: FontWeight.w500, maxWidth: w - 48);
    }
    // buttons, right-aligned, the last one rightmost
    var x = card.right - 24;
    for (final (i, (label, primary)) in d.buttons.indexed.toList().reversed) {
      final bw = ui.measure(label, size: 15, weight: FontWeight.w800).width + 36;
      ui.button('dialog:$label', Rect.fromLTWH(x - bw, card.bottom - 22 - 42, bw, 42), label,
          primary: primary, onTap: () => _answer(i));
      x -= bw + 10;
    }
  }

  // ---- input: UI areas first, then the scene ----

  _Press? _press;

  void _down(PointerDownEvent e) {
    ui.hover = e.localPosition;
    final a = ui.hit(e.localPosition);
    top.anyDown(e.localPosition, a);
    if (a != null && _press == null) {
      _press = _Press(e.pointer, a, e.localPosition);
    } else {
      top.pointerDown(e);
    }
  }

  void _move(PointerMoveEvent e) {
    ui.hover = e.localPosition;
    final p = _press;
    if (p == null || p.pointer != e.pointer) return top.pointerMove(e);
    if (p.toScene) return top.pointerMove(e);
    if (p.dragging) return p.area.onPanUpdate?.call(e.localPosition, e.localDelta);
    final slop = e.kind == PointerDeviceKind.mouse ? 4.0 : kTouchSlop;
    if ((e.localPosition - p.down).distance <= slop || p.longFired) return;
    if (p.area.onPanStart != null) {
      p.dragging = true;
      p.area.onPanStart!(p.down);
      p.area.onPanUpdate?.call(e.localPosition, e.localPosition - p.down);
    } else if (p.area.id != 'barrier' && !p.area.id.startsWith('dialog')) {
      // Not draggable (e.g. a card in a scrolling list): the scene takes the drag.
      p.toScene = true;
      top.pointerDown(PointerDownEvent(
          pointer: e.pointer, position: p.down, kind: e.kind, buttons: e.buttons, timeStamp: e.timeStamp));
      top.pointerMove(e);
    }
  }

  void _up(PointerUpEvent e) {
    final p = _press;
    if (p == null || p.pointer != e.pointer) return top.pointerUp(e);
    _press = null;
    if (p.toScene) return top.pointerUp(e);
    if (p.dragging) return p.area.onPanEnd?.call();
    if (!p.longFired && p.area.rect.contains(e.localPosition)) {
      p.area.onTap?.call();
      p.area.onTapAt?.call(e.localPosition);
    }
  }

  void _cancel(PointerCancelEvent e) {
    final p = _press;
    if (p == null || p.pointer != e.pointer) return top.pointerCancel(e);
    _press = null;
    if (p.toScene) return top.pointerCancel(e);
    if (p.dragging) (p.area.onPanCancel ?? p.area.onPanEnd)?.call();
  }

  @override
  Widget build(BuildContext context) {
    ui.pad = MediaQuery.paddingOf(context);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _cancel,
        onPointerHover: (e) => ui.hover = e.localPosition,
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) top.scroll(e.localPosition, e.scrollDelta.dy);
        },
        child: flame.GameWidget(game: _loop, autofocus: false),
      ),
    );
  }
}
