import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'painter.dart' show ink;

const green = Color(0xFF2E7D32);
const red = Color(0xFFC62828);
const paper = Color(0xFFF7F5F0);

/// A number rounded to thousands / millions: 950, 10,8K, 185K, 1,2M.
String short(num n) {
  final a = n.abs(), sign = n < 0 ? '-' : '';
  String f(double v, String unit) =>
      '$sign${v >= 100 ? v.round() : v.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '').replaceAll('.', ',')}$unit';
  if (a < 1000) return '$sign${a.round()}';
  if (a < 1e6) return f(a / 1000, 'K');
  return f(a / 1e6, 'M');
}

/// Something on screen that reacts to the pointer, registered while drawing a frame.
class UiArea {
  UiArea(this.id, this.rect,
      {this.onTap,
      this.onTapAt,
      this.onLongPress,
      this.onPanStart,
      this.onPanUpdate,
      this.onPanEnd,
      this.onPanCancel});
  final String id;
  final Rect rect;
  final VoidCallback? onTap, onLongPress, onPanEnd, onPanCancel;
  final void Function(Offset at)? onTapAt;
  final void Function(Offset at)? onPanStart;
  final void Function(Offset at, Offset delta)? onPanUpdate;
}

/// The game's UI, drawn straight onto the game canvas each frame (no Flutter widgets): text,
/// icons, boxes and bars, plus the areas that take taps and drags. Pointer events go to the
/// topmost area of the last frame under the finger (see App), else to the scene.
class Ui {
  late Canvas canvas;
  Size size = Size.zero;
  EdgeInsets pad = EdgeInsets.zero; // safe area (notches, rounded corners)
  var _areas = <UiArea>[];
  var _texts = <String>[];

  /// Every text drawn in the last frame (for tests and debugging).
  List<String> texts = const [];

  /// Where the mouse is, if it hovers over the game.
  Offset? hover;

  void begin(Canvas c, Size s) {
    canvas = c;
    size = s;
    _areas = [];
    _texts = [];
  }

  void end() => texts = _texts;

  // ---- text ----

  static final _cache = <Object, TextPainter>{};

  TextPainter _painter(String s, double size, FontWeight weight, Color color, double? maxWidth, int? maxLines,
      TextAlign align, String? family) {
    final key = (s, size, weight, color, maxWidth, maxLines, align, family);
    final hit = _cache.remove(key);
    if (hit != null) return _cache[key] = hit; // most recently used last
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontSize: size, fontWeight: weight, color: color, fontFamily: family, height: family == null ? 1.2 : 1.0),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…',
    )..layout(maxWidth: maxWidth ?? double.infinity);
    if (_cache.length > 600) _cache.remove(_cache.keys.first)?.dispose();
    return _cache[key] = tp;
  }

  Size measure(String s,
          {double size = 13, FontWeight weight = FontWeight.w600, double? maxWidth, int? maxLines}) =>
      _painter(s, size, weight, ink, maxWidth, maxLines, TextAlign.left, null).size;

  /// Draws [s] so that its [anchor] point (e.g. Alignment.center) sits at [at]; returns its box.
  Rect text(String s, Offset at,
      {double size = 13,
      FontWeight weight = FontWeight.w600,
      Color color = ink,
      Alignment anchor = Alignment.topLeft,
      double? maxWidth,
      int? maxLines,
      TextAlign align = TextAlign.left}) {
    final tp = _painter(s, size, weight, color, maxWidth, maxLines, align, null);
    final w = maxWidth != null && align != TextAlign.left ? maxWidth : tp.width;
    final box = anchor.inscribe(Size(w, tp.height), Rect.fromCenter(center: at, width: 0, height: 0));
    tp.paint(canvas, box.topLeft);
    _texts.add(s);
    return box;
  }

  /// A Material icon, drawn from the icon font.
  Rect icon(IconData i, Offset center, {double size = 24, Color color = ink}) {
    final tp = _painter(String.fromCharCode(i.codePoint), size, FontWeight.w400, color, null, null, TextAlign.left,
        i.fontFamily);
    final box = Rect.fromCenter(center: center, width: tp.width, height: tp.height);
    tp.paint(canvas, box.topLeft);
    return box;
  }

  // ---- components ----

  /// The round back button, the same on every screen.
  void back(Offset c, VoidCallback onTap) {
    circle(c, 22, shadow: true);
    icon(Icons.arrow_back, c, size: 24);
    area('back', Rect.fromCircle(center: c, radius: 24), onTap: onTap);
  }

  /// A screen's header: the back button in the top-left corner and [title] beside it,
  /// its capital letters centred on the button (not its line box, which has extra room
  /// below for descenders).
  void header(String title, VoidCallback onBack, {double? maxWidth}) {
    final c = Offset(pad.left + 34, pad.top + 34);
    back(c, onBack);
    const size = 24.0, weight = FontWeight.w900;
    final tp = _painter(title, size, weight, ink, maxWidth, 1, TextAlign.left, null);
    final baseline = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    const capHeight = size * .7;
    text(title, Offset(c.dx + 34, c.dy + capHeight / 2 - baseline), size: size, weight: weight, maxWidth: maxWidth, maxLines: 1);
  }

  // ---- shapes ----

  void box(Rect r,
      {Color fill = Colors.white, double radius = 24, Color? border, double borderWidth = 0, bool shadow = true}) {
    final rr = RRect.fromRectAndRadius(r, Radius.circular(radius));
    if (shadow) {
      canvas.drawRRect(
          rr.shift(const Offset(0, 1)),
          Paint()
            ..color = const Color(0x24000000)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    }
    canvas.drawRRect(rr, Paint()..color = fill);
    if (border != null) {
      canvas.drawRRect(
          rr.deflate(borderWidth / 2),
          Paint()
            ..color = border
            ..style = PaintingStyle.stroke
            ..strokeWidth = borderWidth);
    }
  }

  void circle(Offset c, double r, {Color fill = Colors.white, Color? border, double borderWidth = 3, bool shadow = false}) {
    if (shadow) {
      canvas.drawCircle(
          c + const Offset(0, 1),
          r,
          Paint()
            ..color = const Color(0x24000000)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    }
    canvas.drawCircle(c, r, Paint()..color = fill);
    if (border != null) {
      canvas.drawCircle(
          c,
          r - borderWidth / 2,
          Paint()
            ..color = border
            ..style = PaintingStyle.stroke
            ..strokeWidth = borderWidth);
    }
  }

  /// A progress bar, [f] from 0 to 1.
  void bar(Rect r, double f, Color color, {Color bg = const Color(0x1F000000)}) {
    final rad = Radius.circular(r.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(r, rad), Paint()..color = bg);
    if (f > 0) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(r.left, r.top, max(r.height, r.width * f.clamp(0, 1)), r.height), rad),
          Paint()..color = color);
    }
  }

  /// Everything [draw] paints, at [opacity].
  void faded(double opacity, void Function() draw) {
    if (opacity >= 1) return draw();
    canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
    draw();
    canvas.restore();
  }

  /// Darkens everything drawn so far and catches every touch (for modals).
  void barrier({VoidCallback? onTap, Color color = const Color(0x5A2B2B2B)}) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
    area('barrier', Offset.zero & size, onTap: onTap ?? () {});
  }

  /// A rounded button with a label (and an optional icon); [primary] is filled with ink.
  Rect button(String id, Rect r, String label,
      {VoidCallback? onTap, bool primary = false, IconData? icon, Color? color, double size = 15}) {
    final fg = primary ? Colors.white : (color ?? ink);
    box(r,
        fill: primary ? (color ?? ink) : Colors.white,
        radius: r.height / 2,
        border: primary ? null : (color ?? ink),
        borderWidth: 2,
        shadow: false);
    final tw = measure(label, size: size, weight: FontWeight.w800).width + (icon == null ? 0 : size + 8);
    var x = r.center.dx - tw / 2;
    if (icon != null) {
      this.icon(icon, Offset(x + size / 2, r.center.dy), size: size + 3, color: fg);
      x += size + 8;
    }
    text(label, Offset(x, r.center.dy), size: size, weight: FontWeight.w800, color: fg, anchor: Alignment.centerLeft);
    if (onTap != null) area(id, r, onTap: onTap);
    return r;
  }

  // ---- images ----

  static final _images = <String, ui.Image?>{};

  /// The asset's picture once loaded; null while loading or if there is none.
  ui.Image? image(String asset) {
    if (_images.containsKey(asset)) return _images[asset];
    _images[asset] = null;
    // Future.sync: a missing asset can throw before the future exists
    Future.sync(() => rootBundle.load(asset)).then((data) => ui.instantiateImageCodec(data.buffer.asUint8List())).then(
          (codec) => codec.getNextFrame(),
        ).then<void>((f) => _images[asset] = f.image).catchError((_) {}); // none: callers draw a fallback
    return null;
  }

  /// [img] scaled to cover [r] (cropped at the edges), clipped to its rounded corners.
  void cover(ui.Image img, Rect r, {double radius = 0}) {
    final s = max(r.width / img.width, r.height / img.height);
    final src = Rect.fromCenter(
        center: Offset(img.width / 2, img.height / 2), width: r.width / s, height: r.height / s);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)));
    canvas.drawImageRect(img, src, r, Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
  }

  // ---- input ----

  void area(String id, Rect r,
          {VoidCallback? onTap,
          void Function(Offset at)? onTapAt,
          VoidCallback? onLongPress,
          void Function(Offset at)? onPanStart,
          void Function(Offset at, Offset delta)? onPanUpdate,
          VoidCallback? onPanEnd,
          VoidCallback? onPanCancel}) =>
      _areas.add(UiArea(id, r,
          onTap: onTap,
          onTapAt: onTapAt,
          onLongPress: onLongPress,
          onPanStart: onPanStart,
          onPanUpdate: onPanUpdate,
          onPanEnd: onPanEnd,
          onPanCancel: onPanCancel));

  /// The topmost area under [p] in the last frame.
  UiArea? hit(Offset p) => _areas.reversed.where((a) => a.rect.contains(p)).firstOrNull;

  /// Where the area [id] was in the last frame (for tests and hover checks).
  Rect? rectOf(String id) => _areas.where((a) => a.id == id).lastOrNull?.rect;

  bool hovered(Rect r) => hover != null && r.contains(hover!);
}
