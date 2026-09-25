import 'dart:math';
import 'dart:ui' show Picture, PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'city.dart';
import 'game.dart';
import 'main.dart';
import 'painter.dart';
import 'settings.dart';
import 'ui.dart';

/// The welcome screen's background: a city playing itself. A bot keeps connecting new
/// stations, riders come and go and never give up, and trains carry them. No UI on it.
class Demo {
  Demo(City city) : game = _fresh(city);
  Game game;
  double _think = 0;

  static Game _fresh(City city) => Game(city)
    ..calm = true
    ..endless = true;

  void step(double dt) {
    final g = game..money = 1 << 30;
    g.tick(min(dt, .05) * 1.5);
    g.popups.clear();
    g.sfx.clear();
    g.messageTime = 0;
    if ((_think += dt) < 2) return;
    _think = 0;
    if (g.month >= 18) {
      game = _fresh(g.city); // start over before the map gets crowded
      return;
    }
    _connect(g);
    // one more train as a line grows
    for (final l in g.lines) {
      if (l.trains.length < 1 + l.stops.length ~/ 4) g.addTrain(l, seg: (l.stops.length - 1) ~/ 2, at: 20);
    }
  }

  /// Links the nearest loose station: onto the closest end of a line, or as a new line.
  void _connect(Game g) {
    final onLine = {for (final l in g.lines) ...l.stops};
    final loose = g.stations.where((s) => !onLine.contains(s)).toList();
    if (loose.isEmpty) return;
    if (g.lines.isEmpty) {
      final (a, b) = _closestPair(g.stations);
      g.createLine(a, b);
      return;
    }
    (MetroLine, bool, Station, double)? best;
    for (final s in loose) {
      for (final l in g.lines.where((l) => !l.loop && !l.closing)) {
        for (final head in [true, false]) {
          final end = head ? l.stops.first : l.stops.last;
          final d = (end.pos - s.pos).distance;
          if ((best == null || d < best.$4) && g.canLay(end, s)) best = (l, head, s, d);
        }
      }
    }
    final s = best?.$3 ?? loose.first;
    final hub = onLine.reduce((a, b) => (a.pos - s.pos).distance < (b.pos - s.pos).distance ? a : b);
    // A far-off station gets its own line from the nearest station on the network.
    if ((best == null || best.$4 > 1.6 * (hub.pos - s.pos).distance) && g.nextColor != null && g.canLay(hub, s)) {
      g.createLine(hub, s);
    } else if (best case (final l, final head, final s, _)) {
      g.extend(l, s, atHead: head);
    }
  }

  static (Station, Station) _closestPair(List<Station> ss) {
    var best = (ss[0], ss[1]);
    for (final a in ss) {
      for (final b in ss) {
        if (a != b && (a.pos - b.pos).distance < (best.$1.pos - best.$2.pos).distance) best = (a, b);
      }
    }
    return best;
  }

  /// Fills [size] with the city (cropped to cover it).
  void paint(Canvas canvas, Size size) {
    final s = max(size.width / worldSize.width, size.height / worldSize.height);
    final o = Offset((size.width - worldSize.width * s) / 2, (size.height - worldSize.height * s) / 2);
    canvas.save();
    GamePainter(game, o, s).paint(canvas, size);
    canvas.restore();
  }
}

/// First screen: carry on the city left in progress, pick a city, or open the settings.
class WelcomeScene extends Scene {
  Game? saved;
  int cleared = 0;
  Demo? demo;

  @override
  void enter() => resume();

  @override
  void resume() {
    loadGame().then((g) => saved = g);
    clearedCount().then((n) {
      cleared = n;
      demo ??= Demo(cities[n.clamp(0, cities.length - 1)]);
    });
  }

  @override
  void update(double dt) => demo?.step(dt);

  @override
  void render(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFF4F2EE));
    demo?.paint(canvas, size);
    final g = saved;
    final w = min(380.0, size.width - 32), x = (size.width - w) / 2;
    const bh = 50.0, gap = 12.0;
    final h = 40 + 6 + 20 + 22 + (g == null ? 0 : 64 + gap) + 2 * bh + gap + 28;
    var y = (size.height - h) / 2;
    ui.box(Rect.fromLTWH(x - 20, y - 20, w + 40, h + 16), fill: paper.withValues(alpha: .93), radius: 24);
    ui.text('Metro Kota', Offset(size.width / 2, y), size: 40, weight: FontWeight.w900, anchor: Alignment.topCenter);
    y += 52;
    ui.text('Bangun jaringan kereta di kota-kota besar Indonesia', Offset(size.width / 2, y),
        size: 14, weight: FontWeight.w500, color: Colors.black54, anchor: Alignment.topCenter);
    y += 34;
    if (g != null) {
      final r = Rect.fromLTWH(x, y, w, 64);
      ui.box(r, fill: ink, radius: 32, shadow: false);
      ui.text('▶  Lanjutkan', Offset(r.center.dx, r.top + 10),
          size: 18, weight: FontWeight.w800, color: Colors.white, anchor: Alignment.topCenter);
      ui.text('${g.city.name} · ${monthNames[g.month % 12]} Tahun ${g.month ~/ 12 + 1} · ${rp(g.money)}',
          Offset(r.center.dx, r.top + 36),
          size: 12, weight: FontWeight.w600, color: Colors.white, anchor: Alignment.topCenter);
      ui.area('resume', r, onTap: () => app.push(CityScene(g.city, resume: g)));
      y += 64 + gap;
    }
    ui.button('play', Rect.fromLTWH(x, y, w, bh), g == null ? 'Main' : 'Pilih kota',
        icon: Icons.map_outlined, primary: g == null, onTap: () => app.push(PickerScene()));
    y += bh + gap;
    ui.button('settings', Rect.fromLTWH(x, y, w, bh), 'Pengaturan',
        icon: Icons.settings_outlined, onTap: () => app.push(SettingsScene()));
  }
}

/// The cities, in order: cleared ones can be played again, the next one is open, the rest
/// locked. Scrolls when they don't fit.
class PickerScene extends Scene {
  int cleared = 0;
  var scores = <String, int>{};
  double scrollY = 0;
  final _previews = <Object, Picture>{};

  @override
  void enter() => resume();

  @override
  void resume() {
    clearedCount().then((n) => cleared = n);
    lastScores().then((s) => scores = s);
  }

  @override
  void exit() {
    for (final p in _previews.values) {
      p.dispose();
    }
  }

  @override
  bool key(LogicalKeyboardKey k) {
    if (k != LogicalKeyboardKey.escape) return false;
    app.pop();
    return true;
  }

  /// Opens the city; if it was left in progress, asks whether to carry on.
  Future<void> _play(City city) async {
    final saved = await loadGame();
    var resume = saved?.city == city ? saved : null;
    if (resume != null) {
      final a = await app.ask(
          '${city.name} belum selesai',
          'Lanjutkan dari ${monthNames[resume.month % 12]} Tahun ${resume.month ~/ 12 + 1} (${rp(resume.money)})?',
          [('Mulai ulang', false), ('Lanjutkan', true)]);
      if (a == null) return;
      if (a == 0) resume = null;
    }
    app.push(CityScene(city, resume: resume));
  }

  // ---- scrolling ----
  double _maxScroll = 0;
  Offset? _drag;

  @override
  void pointerDown(PointerEvent e) => _drag = e.localPosition;
  @override
  void pointerMove(PointerEvent e) {
    if (_drag == null) return;
    scrollY = (scrollY - e.localDelta.dy).clamp(0, _maxScroll);
  }

  @override
  void pointerUp(PointerEvent e) => _drag = null;
  @override
  void scroll(Offset p, double dy) => scrollY = (scrollY + dy).clamp(0, _maxScroll);

  @override
  void render(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFE9E6DF));
    final top = ui.pad.top + 76;
    final width = size.width - 32 - ui.pad.horizontal;
    final cols = max(1, (width / (360 + 12)).ceil());
    final cw = (width - (cols - 1) * 12) / cols, ch = cw / .78;
    final rows = (cities.length / cols).ceil();
    _maxScroll = max(0, rows * (ch + 12) + 16 - (size.height - top));
    scrollY = scrollY.clamp(0, _maxScroll);
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, top, size.width, size.height));
    for (final (i, c) in cities.indexed) {
      final r = Rect.fromLTWH(16 + ui.pad.left + (i % cols) * (cw + 12), top + (i ~/ cols) * (ch + 12) - scrollY, cw, ch);
      if (r.bottom > top && r.top < size.height) _card(canvas, c, i, r, top);
    }
    canvas.restore();
    // header on top of the list
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, top), Paint()..color = const Color(0xFFE9E6DF));
    final allDone = cleared >= cities.length;
    ui.header(allDone ? 'Semua kota sudah terhubung!' : 'Metro Kota — kota ${cleared + 1} dari ${cities.length}', app.pop,
        maxWidth: size.width - 260);
    if (allDone) {
      ui.button('reset', Rect.fromLTWH(size.width - ui.pad.right - 196, ui.pad.top + 14, 180, 40), 'Ulang dari awal',
          primary: true, onTap: () async {
        await resetProgress();
        resume();
      });
    }
  }

  void _card(Canvas canvas, City city, int i, Rect r, double clipTop) {
    final open = i <= cleared; // cleared cities can be played again
    ui.box(r, fill: open ? Colors.white : const Color(0xFFD9D6CF), radius: 14);
    const m = 12.0;
    final w = r.width - 2 * m;
    // The same text block on every card (so the rows line up); the map preview takes the rest.
    final score = scores[city.name];
    final blurbH = 2 * ui.measure('M', size: 12, weight: FontWeight.w500).height;
    final textH = 8 + 26 + blurbH + 4 + 18 + 4 + 20 + 4 + 20 + 10;
    final map = Rect.fromLTWH(r.left, r.top, r.width, max(0, r.height - textH));
    _preview(canvas, city, map);
    var y = map.bottom + 8;
    ui.text('${i + 1}. ${city.name}', Offset(r.left + m, y), size: 18, weight: FontWeight.w800, maxWidth: w - 28, maxLines: 1);
    if (i < cleared) {
      ui.icon(Icons.check_circle, Offset(r.right - m - 10, y + 13), size: 20, color: green);
    } else if (!open) {
      ui.icon(Icons.lock_outline, Offset(r.right - m - 10, y + 13), size: 20, color: Colors.black54);
    }
    y += 26;
    ui.text(city.blurb, Offset(r.left + m, y), size: 12, weight: FontWeight.w500, maxWidth: w, maxLines: 2);
    y += blurbH + 4;
    if (score != null) {
      ui.icon(Icons.star_rounded, Offset(r.left + m + 8, y + 9), size: 16, color: green);
      ui.text(short(score), Offset(r.left + m + 22, y + 9),
          size: 12, weight: FontWeight.w800, color: green, anchor: Alignment.centerLeft, maxWidth: w - 22, maxLines: 1);
    }
    y += 18 + 4;
    // icons with rounded numbers: the goals, then what the city is like
    void row(List<(IconData, String)> items) {
      var x = r.left + m;
      for (final (icon, value) in items) {
        ui.icon(icon, Offset(x + 8, y + 10), size: 16, color: Colors.black54);
        x = ui.text(value, Offset(x + 20, y + 10), size: 12, weight: FontWeight.w800, color: Colors.black54, anchor: Alignment.centerLeft)
                .right +
            14;
      }
      y += 24;
    }

    row([
      (Icons.payments_outlined, short(city.goal.money)),
      (Icons.hub_outlined, short(city.goal.stations)),
      (Icons.people_alt_outlined, short(city.goal.riders)),
    ]);
    row([
      (Icons.account_balance_wallet_outlined, short(city.startMoney)),
      (Icons.confirmation_number_outlined, short(city.normalFare)),
      (Icons.water, short(city.bridgeCost)),
      if (city.demand != 1) (Icons.groups_outlined, '×${city.demand}'),
    ]);
    if (open) {
      final hitbox = Rect.fromLTRB(r.left, max(r.top, clipTop), r.right, r.bottom);
      ui.area('city:${city.name}', hitbox, onTap: () => _play(city));
    }
  }

  /// The city's map, recorded once per size and replayed.
  void _preview(Canvas canvas, City city, Rect r) {
    if (r.height < 4) return;
    final key = (city, r.width.round(), r.height.round());
    final pic = _previews[key] ??= () {
      final rec = PictureRecorder(), c = Canvas(rec);
      final s = min(r.width / worldSize.width, r.height / worldSize.height);
      GamePainter(Game(city, spawn: false), Offset((r.width - worldSize.width * s) / 2, 0), s).paint(c, r.size);
      return rec.endRecording();
    }();
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndCorners(r, topLeft: const Radius.circular(14), topRight: const Radius.circular(14)));
    canvas.translate(r.left, r.top);
    canvas.drawPicture(pic);
    canvas.restore();
  }
}

/// Music, sound effects, the FPS meter, and starting over. Kept on the device.
class SettingsScene extends Scene {
  @override
  bool key(LogicalKeyboardKey k) {
    if (k != LogicalKeyboardKey.escape) return false;
    app.pop();
    return true;
  }

  Future<void> _reset() async {
    final a = await app.ask('Mulai dari awal?', 'Semua kota yang sudah selesai dan kota yang sedang dimainkan akan dihapus.',
        [('Batal', false), ('Hapus progres', true)]);
    if (a != 1) return;
    await resetProgress();
    app.toast('Progres dihapus');
  }

  @override
  void render(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFF4F2EE));
    ui.header('Pengaturan', app.pop);
    final w = min(560.0, size.width - 32), x = (size.width - w) / 2;
    var y = ui.pad.top + 80;

    void toggle(String id, IconData icon, String label, bool value, void Function(bool) set) {
      final r = Rect.fromLTWH(x, y, w, 56);
      ui.icon(icon, Offset(r.left + 20, r.center.dy));
      ui.text(label, Offset(r.left + 52, r.center.dy), size: 16, anchor: Alignment.centerLeft);
      // switch
      final track = Rect.fromCenter(center: Offset(r.right - 32, r.center.dy), width: 48, height: 26);
      ui.box(track, fill: value ? ink : const Color(0x33000000), radius: 13, shadow: false);
      ui.circle(Offset(value ? track.right - 13 : track.left + 13, track.center.dy), 10);
      ui.area(id, r, onTap: () {
        set(!value);
        Settings.save();
      });
      y += 56;
    }

    void slider(String id, bool on, double value, void Function(double) set) {
      final r = Rect.fromLTWH(x + 52, y, w - 72, 36);
      ui.faded(on ? 1 : .35, () {
        final track = Rect.fromLTWH(r.left, r.center.dy - 3, r.width, 6);
        ui.bar(track, value, ink);
        ui.circle(Offset(track.left + track.width * value, track.center.dy), 10, fill: ink);
      });
      if (on) {
        void at(Offset p) => set(((p.dx - r.left) / r.width).clamp(0.0, 1.0));
        ui.area(id, r.inflate(6),
            onTapAt: (p) {
              at(p);
              Settings.save();
            },
            onPanStart: at,
            onPanUpdate: (p, _) => at(p),
            onPanEnd: Settings.save);
      }
      y += 40;
    }

    toggle('musicSwitch', Icons.music_note, 'Musik latar', Settings.music, (v) => Settings.music = v);
    slider('musicVolume', Settings.music, Settings.musicVolume, (v) {
      Settings.musicVolume = v;
      Settings.apply();
    });
    toggle('sfxSwitch', Icons.volume_up, 'Efek suara', Settings.sfx, (v) => Settings.sfx = v);
    slider('sfxVolume', Settings.sfx, Settings.sfxVolume, (v) {
      Settings.sfxVolume = v;
      Settings.apply();
    });
    toggle('fpsSwitch', Icons.speed, 'Tampilkan FPS', Settings.showFps, (v) => Settings.showFps = v);
    y += 8;
    canvas.drawLine(Offset(x, y), Offset(x + w, y), Paint()..color = const Color(0x22000000));
    y += 8;
    final r = Rect.fromLTWH(x, y, w, 56);
    ui.icon(Icons.restart_alt, Offset(r.left + 20, r.center.dy), color: red);
    ui.text('Hapus progres', Offset(r.left + 52, r.center.dy), size: 16, color: red, anchor: Alignment.centerLeft);
    ui.area('reset', r, onTap: _reset);
  }
}
