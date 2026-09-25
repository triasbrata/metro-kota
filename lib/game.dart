import 'dart:math';
import 'dart:ui';

import 'cities.dart';

export 'cities.dart';

/// `festival` is never a station's shape: it is a rider's wish to reach [Game.festivalAt]
/// (the station hosting the current event), drawn in purple.
enum Shape { circle, triangle, square, star, diamond, festival }

/// Sound effects, one file each in `assets/sfx/<name>.wav`.
enum Sfx { deliver, build, train, car, station, leave, festival, accident, zone, bridge, goal, error, win, lose }

const worldSize = Size(1000, 620);
const lineColors = [
  Color(0xFFD9534F),
  Color(0xFF2E5EB8),
  Color(0xFF43A047),
  Color(0xFFE8B83A),
  Color(0xFF8E44AD),
  Color(0xFFE67E22),
  Color(0xFF16A085),
];
const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

class Station {
  Station(this.id, this.pos, this.shape);
  final int id;
  final Offset pos;
  final Shape shape;
  final waiting = <Shape>[];
  double wait = 0; // seconds people have waited here since a train last picked anyone up
  double giveUp = 0; // seconds since the last fed-up passenger walked away
  double rep = 1; // reputation: pickups raise it, riders giving up lower it
  double upset = 0; // frustration from walk-outs here: the rest of this station's queue leaves faster

  /// Seconds between walk-outs once the wait ring is full.
  double get giveUpInterval => Game.giveUpEvery / (1 + upset);

  /// Passengers per unit time relative to a fresh station. Long waits scare riders off
  /// (zero at [Game.waitLimit], back after a pickup); reputation scales it up or down.
  double get spawnWeight => rep * max(0, 1 - wait / Game.waitLimit);

  /// A station with a bad name runs out of patience faster.
  double get waitSpeed => 1 / min(1, rep);
}

/// Event area: track may not pass through until the permit is bought.
/// Event area made of cells of the map's hex grid: track may not pass through until the
/// permit is bought.
class Zone {
  Zone(this.name, this.cells, this.price);
  final String name;
  final Set<Hex> cells;
  final int price;
  bool paid = false;

  bool contains(Offset p) => cells.contains(hexAt(p));
  Offset get center => cells.map(hexCenter).reduce((a, b) => a + b) / cells.length.toDouble();
}

// ---- hex grid (pointy-top, axial coordinates) ----

typedef Hex = (int q, int r);
const hexRadius = 38.0;

Offset hexCenter(Hex h) => Offset(hexRadius * sqrt(3) * (h.$1 + h.$2 / 2), hexRadius * 1.5 * h.$2);

List<Offset> hexCorners(Hex h) =>
    [for (var k = 0; k < 6; k++) hexCenter(h) + Offset.fromDirection(pi / 6 + k * pi / 3, hexRadius)];

List<Hex> hexNeighbors(Hex h) =>
    [(h.$1 + 1, h.$2), (h.$1 - 1, h.$2), (h.$1, h.$2 + 1), (h.$1, h.$2 - 1), (h.$1 + 1, h.$2 - 1), (h.$1 - 1, h.$2 + 1)];

/// The cell containing [p] (cube rounding).
Hex hexAt(Offset p) {
  final q = (sqrt(3) / 3 * p.dx - p.dy / 3) / hexRadius, r = (2 / 3 * p.dy) / hexRadius, s = -q - r;
  var rq = q.round(), rr = r.round();
  final rs = s.round();
  final dq = (rq - q).abs(), dr = (rr - r).abs(), ds = (rs - s).abs();
  if (dq > dr && dq > ds) {
    rq = -rr - rs;
  } else if (dr > ds) {
    rr = -rq - rs;
  }
  return (rq, rr);
}

const festivalNames = [
  'Konser Musik',
  'Pertandingan Sepak Bola',
  'Festival Kuliner',
  'Pameran Otomotif',
  'Pawai Budaya',
];

/// Each name is used at most once per city, so a freed area never seems to come back.
/// File name (no extension) of an event's picture in assets/events/: its title in lower case,
/// words joined by "_" (e.g. "Pertandingan Sepak Bola" -> pertandingan_sepak_bola).
String eventImageName(String title) =>
    title.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');

const zoneNames = [
  'Kawasan Cagar Budaya',
  'Lahan Sengketa',
  'Kompleks Militer',
  'Perumahan Elit',
  'Pasar Tradisional',
  'Proyek Jalan Tol',
  'Kawasan Masjid Raya',
  'Tanah Wakaf',
  'Kebun Raya',
  'Kawasan Industri',
  'Lahan Pemakaman',
  'Kampus Negeri',
  'Terminal Bus Lama',
  'Kompleks Stadion',
];

/// A stretch of track over water: points along its deck, the middle, and the water's index
/// in City.water.
typedef Bridge = ({List<Offset> deck, Offset mid, int water});

class MetroLine {
  MetroLine(this.color);
  final Color color;
  final stops = <Station>[];
  final trains = <Train>[];

  /// Tunnels still under construction: segment -> seconds left. Trains can't use them yet.
  final building = <(Station, Station), double>{};
  static (Station, Station) key(Station a, Station b) => a.id < b.id ? (a, b) : (b, a);
  bool isBuilding(Station a, Station b) => building.containsKey(key(a, b));

  /// Crash sites: segment -> distance of the wreck from the segment key's first station,
  /// along route(key.$1, key.$2). No train on this line can pass it.
  final blocked = <(Station, Station), double>{};

  /// Being shut down: runs as a temporary route until its trains finish their trips.
  bool closing = false;

  /// Closed ring: stops.last == stops.first, so every segment is still stops[i]–stops[i+1].
  /// Trains run round and round instead of turning back at the ends.
  bool loop = false;

  /// Segments the player reshaped: segment key -> the point the track is bent through.
  final bends = <(Station, Station), Offset>{};

  /// The track from [a] to [b] (neighbouring stops) as drawn and ridden.
  List<Offset> route(Station a, Station b) => trackRoute(a.pos, b.pos, bends[key(a, b)]);
}

/// Octilinear track from [a] to [b], bent through [via] if given. Symmetric like
/// [pathBetween]: the b->a route is the a->b one reversed.
List<Offset> trackRoute(Offset a, Offset b, [Offset? via]) {
  if (via == null) return pathBetween(a, b);
  // Always worked out in one direction, so b -> a is exactly a -> b reversed.
  if (a.dx > b.dx || (a.dx == b.dx && a.dy > b.dy)) return trackRoute(b, a, via).reversed.toList();
  // Each half has its 45° piece either first or last. Of the four ways, take the one that
  // turns least overall, so the track never folds back on itself around the bend point
  // (straight, a little jog sideways, straight again).
  List<Offset> octi(Offset p, Offset q, bool diagonalFirst) {
    final v = q - p, d = min(v.dx.abs(), v.dy.abs()), diag = Offset(v.dx.sign * d, v.dy.sign * d);
    return [p, diagonalFirst ? p + diag : q - diag, q];
  }

  List<Offset>? best;
  var least = double.infinity;
  for (final first in [false, true]) {
    for (final second in [false, true]) {
      final r = [...octi(a, via, first), ...octi(via, b, second).skip(1)];
      final turn = _turning(r);
      if (turn < least - 1e-6) (best, least) = (r, turn);
    }
  }
  return best!;
}

/// Total of the heading changes along [p] (radians), ignoring zero-length pieces.
double _turning(List<Offset> p) {
  var sum = 0.0;
  double? prev;
  for (var i = 0; i + 1 < p.length; i++) {
    final v = p[i + 1] - p[i];
    if (v.distance < 1e-6) continue;
    if (prev != null) {
      final d = (v.direction - prev).abs() % (2 * pi);
      sum += min(d, 2 * pi - d);
    }
    prev = v.direction;
  }
  return sum;
}

class Train {
  Train(this.line);
  final MetroLine line;
  int seg = 0; // travelling between stops[seg] and stops[seg + 1]
  int dir = 1; // 1: seg -> seg+1, -1: seg+1 -> seg
  double along = 0;
  double dwell = 0;
  int cars = 0; // extra carriages, each carrying another Game.trainCapacity riders
  bool held = false; // picked up by the player to be moved: stands still, not drawn on the track
  int get capacity => Game.trainCapacity * (1 + cars);
  double broken = 0; // seconds left stuck after an accident
  (Station, Station)? crashSite; // key into line.blocked while broken
  final riders = <Shape>[];

  Station get from => dir == 1 ? line.stops[seg] : line.stops[seg + 1];
  Station get to => dir == 1 ? line.stops[seg + 1] : line.stops[seg];
}

class Game {
  /// [spawn]: stations and riders appear by themselves (off in tests that place them).
  /// [fresh] false: start with an empty map, for restoring a save.
  Game(this.city, {int? seed, this.spawn = true, bool fresh = true})
      : rng = Random(seed),
        money = city.startMoney {
    if (spawn && fresh) {
      for (final s in [Shape.circle, Shape.triangle, Shape.square]) {
        spawnStation(s);
      }
    }
  }

  // ---- save / resume ----

  /// A city picked up again where it was left (from [toJson]). The dice start afresh.
  factory Game.fromJson(City city, Map<String, dynamic> j) {
    final g = Game(city, fresh: false);
    double d(Object? v) => (v as num).toDouble();
    List<Shape> shapes(Object? l) => [for (final n in l as List) Shape.values.byName(n as String)];
    for (final (i, s) in (j['stations'] as List).cast<Map<String, dynamic>>().indexed) {
      g.stations.add(Station(i, Offset(d(s['x']), d(s['y'])), Shape.values.byName(s['shape'] as String))
        ..waiting.addAll(shapes(s['waiting']))
        ..wait = d(s['wait'])
        ..giveUp = d(s['giveUp'])
        ..rep = d(s['rep'])
        ..upset = d(s['upset']));
    }
    Station st(Object? id) => g.stations[id as int];
    (Station, Station) key(List e) => MetroLine.key(st(e[0]), st(e[1]));
    for (final z in (j['zones'] as List).cast<Map<String, dynamic>>()) {
      g.zones.add(Zone(z['name'] as String, {for (final c in z['cells'] as List) (c[0] as int, c[1] as int)}, z['price'] as int)
        ..paid = z['paid'] as bool);
    }
    for (final m in (j['lines'] as List).cast<Map<String, dynamic>>()) {
      final l = MetroLine(Color(m['color'] as int))
        ..stops.addAll([for (final id in m['stops'] as List) st(id)])
        ..closing = m['closing'] as bool
        ..loop = m['loop'] as bool;
      for (final e in m['building'] as List) {
        l.building[key(e)] = d(e[2]);
      }
      for (final e in m['blocked'] as List) {
        l.blocked[key(e)] = d(e[2]);
      }
      for (final e in m['bends'] as List) {
        l.bends[key(e)] = Offset(d(e[2]), d(e[3]));
      }
      for (final t in (m['trains'] as List).cast<Map<String, dynamic>>()) {
        l.trains.add(Train(l)
          ..seg = t['seg'] as int
          ..dir = t['dir'] as int
          ..along = d(t['along'])
          ..dwell = d(t['dwell'])
          ..broken = d(t['broken'])
          ..crashSite = t['crash'] == null ? null : key(t['crash'] as List)
          ..riders.addAll(shapes(t['riders']))
          ..cars = t['cars'] as int);
      }
      g.lines.add(l);
    }
    g
      ..money = j['money'] as int
      ..fare = j['fare'] as int
      ..delivered = j['delivered'] as int
      ..lost = j['lost'] as int
      ..anger = d(j['anger'] ?? 0)
      ..calmFor = d(j['calmFor'] ?? 0)
      ..earned = j['earned'] as int
      ..endless = j['endless'] as bool? ?? false
      ..time = d(j['time'])
      ..incomeThisMonth = j['income'] as int
      ..lastIncome = j['lastIncome'] as int
      ..lastCost = j['lastCost'] as int
      .._stationTimer = d(j['stationTimer'])
      .._passengerTimer = d(j['passengerTimer'])
      .._goalsDone = (j['goalsDone'] as List).cast<bool>().toList()
      ..festival = j['festival'] as String?
      ..festivalLeft = d(j['festivalLeft'])
      ..festivalAt = j['festivalAt'] == null ? null : st(j['festivalAt'])
      ..popups.addAll([for (final p in j['popups'] as List) (p[0] as String, p[1] as String, p[2] as String)]);
    return g;
  }

  /// Everything needed to carry on this city later with [Game.fromJson].
  Map<String, Object?> toJson() {
    List<List<Object>> entries<V>(Map<(Station, Station), V> m, List<Object> Function(V) value) =>
        [for (final MapEntry(key: (a, b), value: v) in m.entries) [a.id, b.id, ...value(v)]];
    return {
      'money': money,
      'fare': fare,
      'delivered': delivered,
      'lost': lost,
      'anger': anger,
      'calmFor': calmFor,
      'earned': earned,
      'endless': endless,
      'time': time,
      'income': incomeThisMonth,
      'lastIncome': lastIncome,
      'lastCost': lastCost,
      'stationTimer': _stationTimer,
      'passengerTimer': _passengerTimer,
      'goalsDone': _goalsDone,
      'festival': festival,
      'festivalLeft': festivalLeft,
      'festivalAt': festivalAt?.id,
      'popups': [for (final (icon, title, body) in popups) [icon, title, body]],
      'stations': [
        for (final s in stations)
          {
            'x': s.pos.dx,
            'y': s.pos.dy,
            'shape': s.shape.name,
            'waiting': [for (final w in s.waiting) w.name],
            'wait': s.wait,
            'giveUp': s.giveUp,
            'rep': s.rep,
            'upset': s.upset,
          },
      ],
      'zones': [
        for (final z in zones)
          {
            'name': z.name,
            'cells': [for (final (q, r) in z.cells) [q, r]],
            'price': z.price,
            'paid': z.paid,
          },
      ],
      'lines': [
        for (final l in lines)
          {
            'color': l.color.toARGB32(),
            'stops': [for (final s in l.stops) s.id],
            'closing': l.closing,
            'loop': l.loop,
            'building': entries(l.building, (v) => [v]),
            'blocked': entries(l.blocked, (v) => [v]),
            'bends': entries(l.bends, (p) => [p.dx, p.dy]),
            'trains': [
              for (final t in l.trains)
                {
                  'seg': t.seg,
                  'dir': t.dir,
                  'along': t.along,
                  'dwell': t.dwell,
                  'broken': t.broken,
                  'crash': t.crashSite == null ? null : [t.crashSite!.$1.id, t.crashSite!.$2.id],
                  'riders': [for (final w in t.riders) w.name],
                  'cars': t.cars,
                },
            ],
          },
      ],
    };
  }

  static const monthLength = 30.0; // real seconds per in-game month
  static const trainCapacity = 6;
  // Game over when too many riders walk off angry in a row: each one adds 1 to [anger];
  // after [angerHold] s with nobody leaving it drains by [angerDrain] per second.
  static const angerLimit = 15.0;
  static const angerHold = 5.0;
  static const angerDrain = 1.0;
  static const waitLimit = 15.0;
  static const giveUpEvery = 2.0; // once the wait ring is full, one rider leaves this often
  static const repMin = 0.3, repMax = 2.0, repLoss = 0.15, repGain = 0.03;
  // Walk-outs are contagious within a station: each one raises that station's `upset`, which
  // shortens its give-up interval, and cools down over time. Other stations are unaffected.
  static const upsetPerLoss = 0.4, upsetMax = 4.0, upsetCooldown = 0.1;
  static const trainSpeed = 110.0;
  static const debtLimit = -20000;
  static const segmentCost = 500;
  static const trainCost = 6000;
  static const carCost = trainCost ~/ 5; // an extra carriage: 1/5 of a new train
  static const maxCars = 3;
  static const carPitch = 31.0; // distance between the centres of a train's cars
  static const trainGap = 40.0; // closest a new train's cars may stand to another train's
  static const trainUpkeep = 500;
  static const lineUpkeep = 250;
  static const lineCostStep = 5000; // 2nd line costs this, 3rd twice this, ...
  static const stationEvery = 22.0; // seconds between new stations
  static const fareStep = 50;
  static const tunnelBuildTime = 10.0;
  // A rerouted track keeps its old bridge over the same river if the new crossing is at
  // most this far (world px, ~2 hex cells) from the old deck.
  static const bridgeReach = 160.0;
  static const zoneEvery = 3; // months between zone events
  static const eventChance = 0.35; // chance of a random event at each month change, from month 3
  static const festivalLength = monthLength; // one month
  // During an event the city spawns (1 + festivalBoost)x as many riders; the extra ones
  // all head to the event station.
  static const festivalBoost = 4.0; // an event should feel like a rush: 5x the riders
  static const festivalBurst = 2; // riders per station heading there the moment it starts
  static const accidentStall = 10.0;
  static const crashGap = 35.0; // other trains stop this far short of a wreck
  static const _inf = 1 << 30;

  final City city;
  final Random rng;
  final bool spawn;
  final stations = <Station>[];
  final lines = <MetroLine>[];
  final zones = <Zone>[];
  /// Events waiting to be shown to the player as a pop-up: (icon, title, body).
  final popups = <(String, String, String)>[];

  /// Sound effects asked for since the UI last played them (a set: one of each per frame).
  final sfx = <Sfx>{};
  String? festival; // running event, e.g. 'Konser Musik'
  double festivalLeft = 0;
  Station? festivalAt; // existing station hosting the event
  int money;
  late int fare = city.normalFare;
  int delivered = 0;
  int lost = 0; // riders who gave up waiting
  double anger = 0; // riders who walked off lately (see [angerLimit])
  double calmFor = 0; // seconds since the last one walked off
  int earned = 0; // total fare income, counts towards city.goal.money

  /// Stations on at least one running (not closing) line.
  int get connectedStations => {for (final l in lines) if (!l.closing) ...l.stops}.length;

  /// Progress on the city's goals, in order: money earned, stations connected, riders delivered.
  List<(int have, int need)> get goals => [
        (earned, city.goal.money),
        (connectedStations, city.goal.stations),
        (delivered, city.goal.riders),
      ];
  static const goalNames = ['Capaian uang', 'Stasiun terhubung', 'Penumpang diantar'];

  /// One number for how the city went: connected stations, fare income and riders
  /// delivered, minus riders who gave up and stations left unconnected. Never below 0.
  // ponytail: weights are a first guess; tune once real runs show the balance.
  int get score {
    final connected = connectedStations;
    return max(0, connected * 100 + earned ~/ 100 + delivered * 10 - lost * 20 - (stations.length - connected) * 50);
  }

  /// Cleared once every goal is reached at the same time; there is no time limit.
  bool get won => goals.every((g) => g.$1 >= g.$2);

  /// Chosen after winning: keep playing this city with no end at all (no game over either).
  bool endless = false;

  /// The welcome screen's demo: no events, and riders never give up waiting.
  bool calm = false;

  /// Stopped at the win screen: won and not (yet) playing on endless.
  bool get finished => won && !endless;
  List<bool> _goalsDone = [false, false, false];
  int incomeThisMonth = 0, lastIncome = 0, lastCost = 0;
  double time = 0;
  String? gameOver;
  String? message;
  double messageTime = 0;
  double _stationTimer = stationEvery, _passengerTimer = 2;
  Map<Shape, List<int>>? _dist;

  int get month => time ~/ monthLength; // 0-based months since the start
  int get nextLineCost => lines.isEmpty ? 0 : lineCostStep * lines.length;
  int get trainCount => lines.fold(0, (n, l) => n + l.trains.length);
  int get monthlyCost => trainCount * trainUpkeep + lines.length * lineUpkeep;
  Color? get nextColor => lineColors.where((c) => lines.every((l) => l.color != c)).firstOrNull;

  // Seconds between passengers at one fresh station.
  double get spawnInterval => max(3.5, 9 - month * 0.4) / city.demand;

  /// Fare vs. what locals consider normal: riders paying more expect a faster pickup,
  /// so the wait ring fills this many times faster (0.5 = twice as patient).
  double get farePressure => fare / city.normalFare;

  /// Seconds a fresh station's riders wait before walking out, at the current fare.
  double get patience => waitLimit / farePressure;

  int segmentPrice(Station a, Station b) =>
      segmentCost + (bridgeSpans(a, b).isNotEmpty ? city.bridgeCost : 0);

  void notify(String m) {
    message = m;
    messageTime = 2.5;
  }

  bool _pay(int cost) {
    if (money < cost) {
      notify('Uang kurang: butuh ${rp(cost)}');
      sfx.add(Sfx.error);
      return false;
    }
    money -= cost;
    return true;
  }

  MetroLine? createLine(Station a, Station b) {
    final color = nextColor;
    if (color == null) {
      notify('Semua warna jalur sudah terpakai');
      return null;
    }
    if (_blocked(a, b) || !_pay(nextLineCost + segmentPrice(a, b))) return null;
    final l = MetroLine(color)..stops.addAll([a, b]);
    l.trains.add(Train(l));
    lines.add(l);
    _lay(l, a, b);
    _dist = null;
    sfx.add(Sfx.build);
    return l;
  }

  bool extend(MetroLine l, Station s, {required bool atHead}) {
    if (l.closing || l.loop || l.stops.contains(s)) return false;
    final end = atHead ? l.stops.first : l.stops.last;
    if (_blocked(end, s) || !_pay(segmentPrice(end, s))) return false;
    _lay(l, end, s);
    if (atHead) {
      l.stops.insert(0, s);
      for (final t in l.trains) {
        t.seg++;
      }
    } else {
      l.stops.add(s);
    }
    _dist = null;
    sfx.add(Sfx.build);
    return true;
  }

  /// Joins the line's last stop back to its first (3+ stations): trains then loop.
  bool closeLoop(MetroLine l) {
    if (l.closing || l.loop || l.stops.length < 3) return false;
    final a = l.stops.last, b = l.stops.first;
    if (_blocked(a, b) || !_pay(segmentPrice(a, b))) return false;
    _lay(l, a, b);
    l.stops.add(b);
    l.loop = true;
    _dist = null;
    sfx.add(Sfx.build);
    return true;
  }

  /// Price of bending segment stops[i]–stops[i+1] through [via] (null = back to the plain
  /// route): the track is relaid, and a bridge is paid only where the new shape crosses water
  /// away from the old bridges (same reuse rule as rerouting). Also the bridge flags.
  (int cost, bool fresh, bool reused) reshapeCost(MetroLine l, int i, Offset? via) {
    final a = l.stops[i], b = l.stops[i + 1];
    final pool = _bridges(a, b, l.bends[MetroLine.key(a, b)]);
    final (fresh, reused) = _claimBridges(pool, _bridges(a, b, via));
    return (segmentCost + (fresh ? city.bridgeCost : 0), fresh, reused);
  }

  /// Bends segment stops[i]–stops[i+1] through [via] (null = straighten it). Trains on it
  /// keep their relative place.
  bool reshape(MetroLine l, int i, Offset? via) {
    if (l.closing) return false;
    final a = l.stops[i], b = l.stops[i + 1], key = MetroLine.key(a, b);
    if (_blocked(a, b, via)) return false;
    final (cost, fresh, reused) = reshapeCost(l, i, via);
    if (!_pay(cost)) return false;
    if (reused) notify('Jembatan lama dipakai ulang');
    final oldLen = pathLength(l.route(a, b)), oldLeft = l.building[key];
    via == null ? l.bends.remove(key) : l.bends[key] = via;
    final newLen = pathLength(l.route(a, b));
    l.building.remove(key);
    l.blocked.remove(key);
    if (fresh) {
      l.building[key] = tunnelBuildTime;
    } else if (reused && oldLeft != null) {
      l.building[key] = oldLeft;
    }
    for (final t in l.trains.where((t) => t.seg == i)) {
      t.along *= newLen / oldLen;
      t.broken = 0;
    }
    _dist = null;
    sfx.add(Sfx.build);
    return true;
  }

  /// Reroutes the track between stops[i] and stops[i+1] through [s].
  bool insert(MetroLine l, int i, Station s) => reroute(l, i, [s]);

  /// Reroutes the track between stops[i] and stops[i+1] through [via], in order, as one
  /// change: bridges of the old track are matched against the final route (never against
  /// an in-between version of it), so nothing is paid for track that never gets built.
  bool reroute(MetroLine l, int i, List<Station> via) {
    if (l.closing || via.isEmpty || via.any(l.stops.contains) || via.toSet().length < via.length) return false;
    final a = l.stops[i], b = l.stops[i + 1];
    final chain = [a, ...via, b];
    for (var k = 0; k + 1 < chain.length; k++) {
      if (_blocked(chain[k], chain[k + 1])) return false;
    }
    final oldKey = MetroLine.key(a, b);
    final oldLeft = l.building[oldKey];
    final (cost, bridges) = _reroutePlan(chain, l.bends[oldKey]);
    if (!_pay(cost)) return false;
    if (bridges.any((f) => f.$2)) notify('Jembatan lama dipakai ulang');
    l.building.remove(oldKey);
    l.blocked.remove(oldKey); // rerouted around the wreck
    l.bends.remove(oldKey);
    for (var k = 0; k + 1 < chain.length; k++) {
      final (fresh, reused) = bridges[k];
      if (fresh) {
        l.building[MetroLine.key(chain[k], chain[k + 1])] = tunnelBuildTime;
      } else if (reused && oldLeft != null) {
        l.building[MetroLine.key(chain[k], chain[k + 1])] = oldLeft;
      }
    }
    l.stops.insertAll(i + 1, via);
    for (final t in l.trains) {
      // A train heading back from b towards a now travels b -> the last new stop.
      if (t.seg > i || (t.seg == i && t.dir == -1)) t.seg += via.length;
    }
    _dist = null;
    sfx.add(Sfx.build);
    return true;
  }

  /// Rerouting chain.first–chain.last through the stops in between. Bridges the old track
  /// already has are reused by new track over the same deck: no bridge fee and no rebuild
  /// (an unfinished one keeps its time). Returns the cost and, per new segment, its
  /// (fresh, reused) bridge flags.
  (int cost, List<(bool fresh, bool reused)>) _reroutePlan(List<Station> chain, [Offset? oldVia]) {
    final pool = _bridges(chain.first, chain.last, oldVia);
    final flags = [for (var k = 0; k + 1 < chain.length; k++) _claimBridges(pool, _bridges(chain[k], chain[k + 1]))];
    final cost = (chain.length - 1) * segmentCost + flags.where((f) => f.$1).length * city.bridgeCost;
    return (cost, flags);
  }

  /// What building a drag plan will cost, exactly as the build calls will charge it:
  /// a new line from [anchor] through [stops]; or, with [line], extending from its end
  /// [anchor]; or, with [seg], rerouting stops[seg]–stops[seg+1] through [stops].
  /// [loopTo]: the plan then closes into a loop back to that station.
  int planCost(Station anchor, List<Station> stops, {MetroLine? line, int? seg, Station? loopTo}) {
    if (seg != null) {
      final b = line!.stops[seg + 1];
      return stops.isEmpty ? 0 : _reroutePlan([anchor, ...stops, b], line.bends[MetroLine.key(anchor, b)]).$1;
    }
    var cost = line == null ? nextLineCost : 0;
    var prev = anchor;
    for (final s in stops) {
      cost += segmentPrice(prev, s);
      prev = s;
    }
    return cost + (loopTo == null ? 0 : segmentPrice(prev, loopTo));
  }

  /// Detaches stops[k] from [l]. A middle stop's neighbours are joined directly (reusing
  /// any bridge the new track runs over, paying for new ones); an end stop just shortens the
  /// line. Trains on the removed track move to the nearest remaining neighbour.
  bool detach(MetroLine l, int k) {
    if (l.closing) return false;
    if (l.stops.length <= (l.loop ? 4 : 2)) {
      notify('Jalur minimal ${l.loop ? 3 : 2} stasiun. Tahan warna jalurnya untuk menutup jalur');
      return false;
    }
    if (l.loop && (k == 0 || k == l.stops.length - 1)) {
      // The loop's join station: rotate the ring one stop so it sits in the middle.
      final segs = l.stops.length - 1;
      l.stops
        ..removeAt(0)
        ..add(l.stops.first);
      for (final t in l.trains) {
        t.seg = (t.seg - 1 + segs) % segs;
      }
      k = segs - 1;
    }
    final n = l.stops.length, s = l.stops[k];
    final prev = k > 0 ? l.stops[k - 1] : null, next = k < n - 1 ? l.stops[k + 1] : null;
    final oldKeys = [if (prev != null) MetroLine.key(prev, s), if (next != null) MetroLine.key(s, next)];
    if (prev != null && next != null) {
      if (_blocked(prev, next)) return false;
      final pool = [
        ..._bridges(prev, s, l.bends[MetroLine.key(prev, s)]),
        ..._bridges(s, next, l.bends[MetroLine.key(s, next)]),
      ];
      final oldLeft = oldKeys.map((key) => l.building[key]).nonNulls.fold<double?>(null, (m, v) => max(m ?? 0, v));
      final (fresh, reused) = _claimBridges(pool, _bridges(prev, next));
      if (!_pay(fresh ? city.bridgeCost : 0)) return false;
      if (fresh) {
        l.building[MetroLine.key(prev, next)] = tunnelBuildTime;
      } else if (reused && oldLeft != null) {
        l.building[MetroLine.key(prev, next)] = oldLeft;
      }
    }
    for (final key in oldKeys) {
      l.building.remove(key);
      l.blocked.remove(key);
      l.bends.remove(key);
    }
    l.stops.removeAt(k);
    final last = l.stops.length - 1;
    for (final t in l.trains) {
      if (t.seg == k - 1 || t.seg == k) {
        // Was on track touching s: wait at the neighbour instead.
        final at = min(max(k - 1, 0), last);
        t
          ..seg = at < last ? at : at - 1
          ..dir = at < last ? 1 : -1
          ..along = 0
          ..broken = 0;
      } else if (t.seg > k) {
        t.seg--;
      }
    }
    _dist = null;
    sfx.add(Sfx.build);
    return true;
  }

  /// Can planned track run from [a] to [b]? False (with a message) through an unpaid permit zone.
  bool canLay(Station a, Station b) => !_blocked(a, b);

  bool _blocked(Station a, Station b, [Offset? via]) {
    final route = trackRoute(a.pos, b.pos, via);
    final z = zones.where((z) => !z.paid && routeHits(route, z.contains)).firstOrNull;
    if (z != null) notify('${z.name}: bayar izin ${rp(z.price)} dulu (ketuk areanya)');
    return z != null;
  }

  Zone? zoneAt(Offset p) => zones.where((z) => !z.paid && z.contains(p)).firstOrNull;

  void buyZone(Zone z) {
    if (_pay(z.price)) {
      z.paid = true;
      notify('Izin ${z.name} dibeli, rel boleh lewat');
      sfx.add(Sfx.build);
    }
  }

  /// Zone event: 3–4 neighbouring land cells of the hex grid, somewhere no track runs yet
  /// and not touching another zone.
  Zone? spawnZone() {
    bool usable(Hex c) {
      final p = hexCenter(c);
      return p.dx > 20 && p.dy > 20 && p.dx < worldSize.width - 20 && p.dy < worldSize.height - 20 && !isWater(p);
    }

    // Zones stay in [zones] after being paid for, so freed land is never offered again: new
    // cells must not overlap or touch any zone, paid or not, and names are never reused.
    final names = zoneNames.where((n) => zones.every((z) => z.name != n)).toList();
    if (names.isEmpty) return null;
    for (var i = 0; i < 40; i++) {
      final cells = {hexAt(Offset(rng.nextDouble() * worldSize.width, rng.nextDouble() * worldSize.height))};
      final size = 3 + rng.nextInt(2);
      while (cells.length < size) {
        cells.add(hexNeighbors(cells.elementAt(rng.nextInt(cells.length)))[rng.nextInt(6)]);
      }
      if (!cells.every(usable)) continue;
      if (zones.any((z) => z.cells.any((c) => cells.contains(c) || hexNeighbors(c).any(cells.contains)))) continue;
      final z = Zone(names[rng.nextInt(names.length)], cells, 6000 + month * 800);
      final tracked = lines.any((l) => [
            for (var j = 0; j + 1 < l.stops.length; j++) l.route(l.stops[j], l.stops[j + 1])
          ].any((route) => routeHits(route, z.contains)));
      if (tracked) continue;
      zones.add(z);
      sfx.add(Sfx.zone);
      popups.add(('🚧', z.name,
          'Rel yang melewati kawasan oranye ini harus bayar izin ${rp(z.price)} dulu. Ketuk kawasannya untuk membayar.'));
      return z;
    }
    return null;
  }

  /// New track across water starts as a tunnel under construction.
  void _lay(MetroLine l, Station a, Station b) {
    if (bridgeSpans(a, b, l.bends[MetroLine.key(a, b)]).isNotEmpty) l.building[MetroLine.key(a, b)] = tunnelBuildTime;
  }

  /// Each bridge on the a–b track: the deck (points every 4px along the track over water),
  /// its midpoint, and which of the city's waters it spans.
  List<Bridge> _bridges(Station a, Station b, [Offset? via]) {
    final key = MetroLine.key(a, b);
    final route = trackRoute(key.$1.pos, key.$2.pos, via);
    return [
      for (final (from, to) in bridgeSpans(a, b, via))
        (
          deck: [for (var d = from; d < to; d += 4) pointAlong(route, d).$1, pointAlong(route, to).$1],
          mid: pointAlong(route, (from + to) / 2).$1,
          water: _waterOf(pointAlong(route, (from + to) / 2).$1),
        ),
    ];
  }

  /// Index in city.water of the water at [p], or -1 on land.
  int _waterOf(Offset p) {
    for (var i = 0; i < city.water.length; i++) {
      final w = city.water[i];
      if (w.sea ? (Path()..addPolygon(w.points, true)).contains(p) : distToPolyline(p, w.points) < w.width / 2) {
        return i;
      }
    }
    return -1;
  }

  /// Matches a new segment's bridges against the old track's ([pool], each old bridge used
  /// at most once). When track is rerouted, an old bridge moves along with it: a new
  /// crossing of the same river within [bridgeReach] of the old deck reuses it (e.g. the
  /// route now bends through a station on an island between two bridged rivers). Crossing
  /// the river far away, or crossing it a second time, is a new bridge.
  /// fresh = needs a new bridge, reused = rides on an old one.
  (bool fresh, bool reused) _claimBridges(List<Bridge> pool, List<Bridge> bridges) {
    var fresh = false, reused = false;
    for (final b in bridges) {
      Bridge? old;
      var best = bridgeReach;
      for (final o in pool.where((o) => o.water == b.water)) {
        final d = distToPolyline(b.mid, o.deck);
        if (d <= best) (old, best) = (o, d);
      }
      old != null && pool.remove(old) ? reused = true : fresh = true;
    }
    return (fresh, reused);
  }

  /// Tip of the terminal "T" cap drawn past the head or tail of [l].
  Offset capTip(MetroLine l, {required bool head}) {
    final end = head ? l.stops.first : l.stops.last;
    final prev = head ? l.stops[1] : l.stops[l.stops.length - 2];
    final route = l.route(prev, end);
    final dir = route.last - route[route.length - 2];
    return end.pos + dir / max(dir.distance, 1) * 26;
  }

  /// Line cap under [p], preferring [prefer] where lines overlap.
  (MetroLine, bool head)? capAt(Offset p, [MetroLine? prefer]) {
    for (final l in [?prefer, ...lines].where((l) => !l.closing && !l.loop)) {
      for (final head in [true, false]) {
        if ((capTip(l, head: head) - p).distance < 24) return (l, head);
      }
    }
    return null;
  }

  /// Track segment (line, index of its first stop) under [p].
  (MetroLine, int)? segmentAt(Offset p, [MetroLine? prefer]) {
    for (final l in [?prefer, ...lines].where((l) => !l.closing)) {
      for (var i = 0; i + 1 < l.stops.length; i++) {
        if (distToPolyline(p, l.route(l.stops[i], l.stops[i + 1])) < 20) return (l, i);
      }
    }
    return null;
  }

  /// Closing is gradual: the line keeps running as a temporary route until every train has
  /// finished its riders' trips (see [_serve] and [tick]), then it disappears.
  void closeLine(MetroLine l) {
    l.closing = true;
    _dist = null; // nobody new plans a trip over it
    notify('Jalur ditutup setelah semua kereta menyelesaikan perjalanannya');
  }

  /// Puts a new train on track stops[seg]–stops[seg+1], [at] px from stops[seg], heading
  /// towards stops[seg+1] (dir 1) or back towards stops[seg] (dir -1).
  bool addTrain(MetroLine l, {int seg = 0, int dir = 1, double at = 0}) {
    final t = _placeable(l, seg, dir, at, what: 'menambahkan');
    if (t == null || !_pay(trainCost)) return false;
    l.trains.add(t);
    sfx.add(Sfx.train);
    return true;
  }

  /// Lifts [t] off its track and sets it down on [l] (the same line or another), [at] px
  /// from stops[seg], heading for stops[seg+1] (dir 1) or back to stops[seg] (-1). Free;
  /// riders and carriages stay on board. Returns the train now on [l], or null if refused
  /// (it then stays where it was).
  Train? moveTrain(Train t, MetroLine l, {required int seg, required int dir, required double at}) {
    t.held = false;
    if (t.line.closing || t.broken > 0) return null;
    final moved = _placeable(l, seg, dir, at, cars: t.cars, except: t, what: 'memindahkan');
    if (moved == null) return null;
    t.line.trains.remove(t);
    l.trains.add(moved..riders.addAll(t.riders));
    sfx.add(Sfx.train);
    return moved;
  }

  /// Could a train (with [cars] carriages) stand there? Not on an unfinished tunnel, and not
  /// crowding another train of the line: every car keeps [trainGap] from every car of the
  /// others (besides [except], the one being moved).
  bool fitsTrain(MetroLine l, int seg, int dir, double at, {int cars = 0, Train? except}) =>
      !l.closing && !l.isBuilding(l.stops[seg], l.stops[seg + 1]) && !_crowded(_train(l, seg, dir, at, cars), except);

  Train _train(MetroLine l, int seg, int dir, double at, int cars) {
    final len = pathLength(l.route(l.stops[seg], l.stops[seg + 1]));
    return Train(l)
      ..seg = seg
      ..dir = dir
      ..along = (dir == 1 ? at : len - at).clamp(0, len)
      ..cars = cars;
  }

  bool _crowded(Train t, Train? except) {
    List<Offset> cars(Train x) => [for (var k = 0; k <= x.cars; k++) trackBehind(x, k * carPitch).pos];
    final mine = cars(t);
    return t.line.trains
        .where((o) => o != except)
        .any((o) => cars(o).any((p) => mine.any((q) => (p - q).distance < trainGap)));
  }

  /// The train to put down, or null (with the reason told to the player) if it can't go there.
  Train? _placeable(MetroLine l, int seg, int dir, double at, {int cars = 0, Train? except, required String what}) {
    if (l.closing) return null;
    if (l.isBuilding(l.stops[seg], l.stops[seg + 1])) {
      notify('Terowongan belum selesai: taruh kereta di rel lain');
      return null;
    }
    final t = _train(l, seg, dir, at, cars);
    if (_crowded(t, except)) {
      notify('Gagal $what kereta: terlalu dekat dengan kereta lain');
      sfx.add(Sfx.error);
      return null;
    }
    return t;
  }

  /// Hooks a carriage onto [t]: [trainCapacity] more seats.
  bool addCar(Train t) {
    if (t.line.closing) return false;
    if (t.cars >= maxCars) {
      notify('Kereta ini sudah membawa $maxCars gerbong');
      return false;
    }
    if (!_pay(carCost)) return false;
    t.cars++;
    sfx.add(Sfx.car);
    return true;
  }

  /// A carriage dropped on [l]'s track goes to its train with the fewest carriages (the one
  /// nearest [near] on a tie); null if every train is full (or there is none).
  Train? trainForCar(MetroLine l, Offset near) {
    final open = l.trains.where((t) => t.cars < maxCars).toList();
    if (l.closing || open.isEmpty) return null;
    double dist(Train t) => (trackBehind(t, 0).pos - near).distance;
    return open.reduce((a, b) => a.cars != b.cars ? (a.cars < b.cars ? a : b) : (dist(a) <= dist(b) ? a : b));
  }

  /// Train (on a running line) whose middle is within [r] of [p].
  Train? trainAt(Offset p, [double r = 28]) {
    for (final l in lines.where((l) => !l.closing)) {
      for (final t in l.trains) {
        if ((pointAlong(l.route(t.from, t.to), t.along).$1 - p).distance < r) return t;
      }
    }
    return null;
  }

  Station? stationAt(Offset p, [double r = 28]) =>
      stations.where((s) => (s.pos - p).distance < r).firstOrNull;

  void tick(double dt) {
    if (gameOver != null || finished) return;
    // A new city waits for its first track: no riders, no new stations, no months passing.
    if (spawn && time == 0 && lines.isEmpty) return;
    final prevMonth = month;
    time += dt;
    if (messageTime > 0) messageTime -= dt;
    if (festival != null) {
      final wasOpen = festivalOpen;
      festivalLeft -= dt;
      if (wasOpen && !festivalOpen) notify('$festival tutup');
      // Gone once the last rider bound for it has arrived or walked away (or, should one be
      // stranded on a train, after one more month).
      if (!festivalOpen && (festivalRiders == 0 || festivalLeft <= -festivalLength)) _endFestival();
    }
    if (spawn) {
      if ((_stationTimer -= dt) <= 0) {
        _stationTimer = stationEvery;
        if (spawnStation() != null) sfx.add(Sfx.station);
      }
      // The city's spawn clock runs at the summed station weights: neglect slows it, good service
      // speeds it up, and an event speeds it up further.
      final clock = stations.fold(0.0, (n, s) => n + s.spawnWeight) * (festivalOpen ? 1 + festivalBoost : 1);
      if ((_passengerTimer -= dt * clock) <= 0) {
        _passengerTimer = spawnInterval;
        spawnPassenger();
      }
    }
    for (final l in lines) {
      final pending = l.building.length;
      l.building
        ..updateAll((_, left) => left - dt)
        ..removeWhere((_, left) => left <= 0);
      if (l.building.length < pending) {
        _dist = null;
        notify('Terowongan selesai dibangun');
        sfx.add(Sfx.bridge);
      }
      for (final t in l.trains) {
        _move(t, dt);
      }
      // Closing line: an empty train that has pulled into a station is retired.
      if (l.closing) l.trains.removeWhere((t) => t.riders.isEmpty && t.along == 0 && t.broken <= 0);
    }
    lines.removeWhere((l) => l.closing && l.trains.isEmpty);
    for (final s in stations) {
      s.upset = max(0, s.upset - upsetCooldown * dt);
      s.wait = s.waiting.isEmpty || calm ? 0 : s.wait + dt * s.waitSpeed * farePressure;
      if (s.wait < waitLimit) {
        s.giveUp = 0;
      } else if ((s.giveUp += dt) >= s.giveUpInterval) {
        s.giveUp = 0;
        s.waiting.removeAt(0); // longest-waiting rider walks away
        s.rep = max(repMin, s.rep - repLoss);
        s.upset = min(upsetMax, s.upset + upsetPerLoss);
        sfx.add(Sfx.leave);
        lost++;
        anger++;
        calmFor = 0;
      }
    }
    // Anger drains once nobody has walked off for a while; too much at once ends the city
    // (never in endless mode).
    if ((calmFor += dt) > angerHold) anger = max(0, anger - angerDrain * dt);
    if (anger >= angerLimit && !endless) gameOver = 'Terlalu banyak warga marah dan pergi!';
    if (month > prevMonth) _endOfMonth();
    // Cheer each goal as it is reached (stations can drop again if track is removed).
    final done = [for (final (have, need) in goals) have >= need];
    for (var i = 0; i < done.length; i++) {
      if (done[i] && !_goalsDone[i] && !won) {
        notify('${goalNames[i]} tercapai! 🎯');
        sfx.add(Sfx.goal);
      }
    }
    _goalsDone = done;
  }

  void _endOfMonth() {
    lastCost = monthlyCost;
    lastIncome = incomeThisMonth;
    incomeThisMonth = 0;
    money -= lastCost;
    if (calm) {
      // the welcome screen's demo: no events at all
    } else if (spawn && month % zoneEvery == 0) {
      spawnZone();
    } else if (spawn && month >= 2 && rng.nextDouble() < eventChance) {
      rng.nextBool() ? startFestival() : accident();
    }
    if (money < debtLimit && !endless) gameOver ='Bangkrut! Utang lewat ${rp(-debtLimit)}';
  }

  void _move(Train t, double dt) {
    if (t.held) return;
    if (t.broken > 0) {
      if ((t.broken -= dt) <= 0) t.line.blocked.remove(t.crashSite);
      return;
    }
    if (t.dwell > 0) {
      t.dwell -= dt;
      return;
    }
    if (t.along == 0 && t.line.isBuilding(t.from, t.to) && !_turnBack(t)) return; // wait for the tunnel
    final len = pathLength(t.line.route(t.from, t.to));
    var next = t.along + trainSpeed * dt;
    final key = MetroLine.key(t.from, t.to);
    if (t.line.blocked[key] case final wreck?) {
      // Queue up short of the wreck if it's still ahead of us.
      final ahead = t.from == key.$1 ? wreck : len - wreck;
      if (t.along <= ahead) next = min(next, max(t.along, ahead - crashGap));
    }
    t.along = next;
    if (t.along < len) return;
    var k = t.dir == 1 ? t.seg + 1 : t.seg; // index of the stop we reached
    final last = t.line.stops.length - 1;
    if (t.line.loop) {
      // Round and round: the join station is both stops[0] and stops[last].
      if (t.dir == 1) {
        t.seg = k == last ? 0 : k;
        if (k == last) k = 0;
      } else {
        t.seg = k == 0 ? last - 1 : k - 1;
        if (k == 0) k = last;
      }
    } else if (t.dir == 1) {
      k == last ? t.dir = -1 : t.seg++;
    } else {
      k == 0 ? t.dir = 1 : t.seg--;
    }
    t.along = 0;
    t.dwell = 0.4;
    _serve(t, k);
  }

  /// Turns a train around at its station instead of entering an unfinished tunnel.
  bool _turnBack(Train t) {
    final l = t.line, k = l.stops.indexOf(t.from); // a loop's join station gives 0
    final back = k > 0 ? k - 1 : (l.loop ? l.stops.length - 2 : -1); // segment behind us
    if (t.dir == 1 && back >= 0 && !l.isBuilding(l.stops[back], l.stops[back + 1])) {
      t.dir = -1;
      t.seg = back;
    } else if (t.dir == -1 && k + 1 < l.stops.length && !l.isBuilding(l.stops[k], l.stops[k + 1])) {
      t.dir = 1;
      t.seg = k;
    } else {
      return false;
    }
    _serve(t, k); // riders re-plan for the new direction
    return true;
  }

  void _serve(Train t, int k) {
    final stops = t.line.stops;
    final s = stops[k];
    // On a loop every other stop comes round eventually.
    final ahead = t.line.loop
        ? stops.where((x) => x != s).toList()
        : t.dir == 1
            ? stops.sublist(k + 1)
            : stops.sublist(0, k);
    int best(Shape w) => ahead.fold(_inf, (m, x) => min(m, dist(w, x)));
    if (t.line.closing) {
      // Winding down: finish trips whose stop is still ahead, drop everyone else off
      // to transfer, and take nobody new.
      t.riders.removeWhere((w) {
        if (_isDestination(w, s)) return _deliver();
        if (ahead.any((x) => _isDestination(w, x))) return false;
        s.waiting.add(w);
        return true;
      });
      return;
    }
    t.riders.removeWhere((w) {
      if (_isDestination(w, s)) return _deliver();
      if (best(w) >= dist(w, s)) {
        s.waiting.add(w); // transfer: nothing ahead gets them closer
        return true;
      }
      return false;
    });
    s.waiting.removeWhere((w) {
      if (t.riders.length >= t.capacity || best(w) >= dist(w, s)) return false;
      t.riders.add(w);
      s.wait = 0;
      s.rep = min(repMax, s.rep + repGain);
      return true;
    });
  }

  /// A rider reached their stop: collect the fare. Returns true (rider leaves the train).
  bool _deliver() {
    delivered++;
    sfx.add(Sfx.deliver);
    money += fare;
    earned += fare;
    incomeThisMonth += fare;
    return true;
  }

  bool _isDestination(Shape w, Station s) => w == s.shape || (w == Shape.festival && s == festivalAt);

  /// Hops from [s] to the nearest station of shape [w] over the whole network.
  int dist(Shape w, Station s) => (_dist ??= _computeDist())[w]![s.id];

  Map<Shape, List<int>> _computeDist() {
    final adj = List.generate(stations.length, (_) => <int>[]);
    for (final l in lines.where((l) => !l.closing)) {
      for (var i = 0; i + 1 < l.stops.length; i++) {
        if (l.isBuilding(l.stops[i], l.stops[i + 1])) continue;
        adj[l.stops[i].id].add(l.stops[i + 1].id);
        adj[l.stops[i + 1].id].add(l.stops[i].id);
      }
    }
    return {
      for (final shape in Shape.values)
        shape: () {
          final d = List.filled(stations.length, _inf);
          final q = <int>[];
          for (final s in stations.where((s) => _isDestination(shape, s))) {
            d[s.id] = 0;
            q.add(s.id);
          }
          for (var i = 0; i < q.length; i++) {
            for (final n in adj[q[i]]) {
              if (d[n] == _inf) {
                d[n] = d[q[i]] + 1;
                q.add(n);
              }
            }
          }
          return d;
        }(),
    };
  }

  Station? spawnStation([Shape? shape]) {
    if (stations.length >= 30) return null;
    final r = rng.nextDouble();
    shape ??= r < .5
        ? Shape.circle
        : r < .75
            ? Shape.triangle
            : r < .9
                ? Shape.square
                : r < .95
                    ? Shape.star
                    : Shape.diamond;
    // The city grows outward from the centre as stations are added.
    final f = min(1.0, 0.4 + stations.length * 0.04);
    final c = worldSize.center(Offset.zero);
    for (var i = 0; i < 50; i++) {
      final p = c +
          Offset((rng.nextDouble() - .5) * (worldSize.width - 120) * f,
              (rng.nextDouble() - .5) * (worldSize.height - 120) * f);
      if (stations.any((s) => (s.pos - p).distance < 80)) continue;
      if (_onWater(p)) continue;
      return addStation(p, shape);
    }
    return null;
  }

  Station addStation(Offset p, Shape shape) {
    final s = Station(stations.length, p, shape);
    stations.add(s);
    _dist = null;
    return s;
  }

  bool _onWater(Offset p) => city.water.any((w) =>
      distToPolyline(p, w.outline) < w.width / 2 + 25 || (w.sea && (Path()..addPolygon(w.points, true)).contains(p)));

  late final _seas = [for (final w in city.water) if (w.sea) Path()..addPolygon(w.points, true)];

  /// Is [p] on the water itself (inside a sea, or within a river's banks)?
  bool isWater(Offset p) =>
      _seas.any((s) => s.contains(p)) || city.water.any((w) => !w.sea && distToPolyline(p, w.points) < w.width / 2);

  final _bridgeCache = <((Station, Station), Offset?), List<(double, double)>>{};

  /// Stretches of the a–b track (bent through [via], if reshaped) that run over water, as
  /// (start, end) distances along trackRoute(key.$1.pos, key.$2.pos, via) with
  /// key = MetroLine.key(a, b). Cached: stations never move.
  // ponytail: sampled every 3px, so a bridge edge can be off by up to 3px.
  List<(double, double)> bridgeSpans(Station a, Station b, [Offset? via]) {
    final key = MetroLine.key(a, b);
    return _bridgeCache[(key, via)] ??= () {
      final route = trackRoute(key.$1.pos, key.$2.pos, via);
      final len = pathLength(route);
      final wet = isWater;
      final spans = <(double, double)>[];
      double? start;
      for (var d = 0.0;; d = min(len, d + 3)) {
        final w = wet(pointAlong(route, d).$1);
        if (w && start == null) start = d;
        if ((!w || d >= len) && start != null) {
          spans.add((start, d));
          start = null;
        }
        if (d >= len) break;
      }
      return spans;
    }();
  }

  bool crossesWater(Offset a, Offset b) {
    final p = pathBetween(a, b);
    for (final w in city.water) {
      final o = w.outline;
      for (var i = 0; i + 1 < p.length; i++) {
        for (var j = 0; j + 1 < o.length; j++) {
          if (_intersect(p[i], p[i + 1], o[j], o[j + 1])) return true;
        }
      }
    }
    return false;
  }

  void spawnPassenger() {
    if (stations.length < 2) return;
    var r = rng.nextDouble() * stations.fold(0.0, (n, s) => n + s.spawnWeight);
    final s = stations.firstWhere((s) => (r -= s.spawnWeight) < 0, orElse: () => stations.first);
    if (s.spawnWeight == 0) return; // every station is fed up
    // The event's extra riders: boost / (1 + boost) of all spawns while it runs.
    if (festivalOpen && s != festivalAt && rng.nextDouble() < festivalBoost / (1 + festivalBoost)) {
      s.waiting.add(Shape.festival);
      return;
    }
    final wants = stations.map((x) => x.shape).toSet()..remove(s.shape);
    if (wants.isEmpty) return;
    s.waiting.add(wants.elementAt(rng.nextInt(wants.length)));
  }

  /// Random event at an existing station: for one month every station spawns extra riders,
  /// all heading to it.
  bool startFestival() {
    if (festival != null || stations.length < 2) return false;
    festivalAt = stations[rng.nextInt(stations.length)];
    festival = festivalNames[rng.nextInt(festivalNames.length)];
    festivalLeft = festivalLength;
    _dist = null;
    // The rush starts at once: every other station fills up with visitors.
    for (final s in stations.where((s) => s != festivalAt)) {
      s.waiting.addAll(List.filled(festivalBurst, Shape.festival));
    }
    sfx.add(Sfx.festival);
    popups.add(('🎉', festival!,
        'Bulan ini ada acara di stasiun yang ditandai ungu. Penumpang dari semua stasiun bertambah '
            'dan menuju ke sana. Sambungkan stasiun itu ke jalurmu supaya pendapatan melonjak!'));
    return true;
  }

  /// The event's time is up ([festivalLeft] ≤ 0): no new riders head there, but it stays
  /// (still the destination) until the riders already on their way are gone.
  bool get festivalOpen => festival != null && festivalLeft > 0;

  /// Riders waiting for or riding to the event.
  int get festivalRiders =>
      stations.fold(0, (n, s) => n + s.waiting.where((w) => w == Shape.festival).length) +
      lines.fold(0, (n, l) => n + l.trains.fold(0, (m, t) => m + t.riders.where((w) => w == Shape.festival).length));

  /// The event disappears. Riders still heading there (only if stranded past the grace
  /// month) now just want the host station's shape.
  void _endFestival() {
    final host = festivalAt!;
    List<Shape> retarget(List<Shape> l) => [for (final w in l) w == Shape.festival ? host.shape : w];
    for (final s in stations) {
      s.waiting.setAll(0, retarget(s.waiting));
    }
    for (final l in lines) {
      for (final t in l.trains) {
        t.riders.setAll(0, retarget(t.riders));
      }
    }
    notify('$festival selesai');
    festival = festivalAt = null;
    _dist = null;
  }

  /// Random event: a train crashes. Compensation is owed even if it puts us in debt.
  /// The wreck also blocks its segment: other trains on the line stop short of it.
  Train? accident([Train? train]) {
    final trains = [for (final l in lines) ...l.trains];
    if (trains.isEmpty) return null;
    final t = train ?? trains[rng.nextInt(trains.length)];
    final fine = 3000 + month * 300;
    money -= fine;
    t.broken = accidentStall;
    final key = t.crashSite = MetroLine.key(t.from, t.to);
    final len = pathLength(t.line.route(t.from, t.to));
    t.line.blocked[key] = t.from == key.$1 ? t.along : len - t.along;
    sfx.add(Sfx.accident);
    popups.add(('🚨', 'Kecelakaan kereta!',
        'Kamu wajib membayar ganti rugi ${rp(fine)}. Jalur di titik ⚠ tertutup ${accidentStall.toInt()} detik: '
            'kereta lain di jalur itu tertahan sebelum lokasi kecelakaan.'));
    return t;
  }
}

/// Rupiah with dot thousand separators: rp(24000) == 'Rp24.000'.
String rp(int v) {
  final digits = v.abs().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '${v < 0 ? '-' : ''}Rp$digits';
}

// ---- geometry ----

/// Octilinear route like a metro map: straight run, then a 45° diagonal.
/// Symmetric: a->b is b->a reversed, so trains in both directions follow the drawn track.
List<Offset> pathBetween(Offset a, Offset b) {
  if (a.dx > b.dx || (a.dx == b.dx && a.dy > b.dy)) return pathBetween(b, a).reversed.toList();
  final dx = b.dx - a.dx, dy = b.dy - a.dy;
  final mid = dx.abs() > dy.abs()
      ? Offset(a.dx + dx.sign * (dx.abs() - dy.abs()), a.dy)
      : Offset(a.dx, a.dy + dy.sign * (dy.abs() - dx.abs()));
  return [a, mid, b];
}

double pathLength(List<Offset> p) {
  var d = 0.0;
  for (var i = 0; i + 1 < p.length; i++) {
    d += (p[i + 1] - p[i]).distance;
  }
  return d;
}

/// Point at distance [d] along [p], plus the heading angle there.
(Offset, double) pointAlong(List<Offset> p, double d) {
  for (var i = 0; i + 1 < p.length; i++) {
    final v = p[i + 1] - p[i];
    if (d <= v.distance || i + 2 == p.length) {
      final t = v.distance == 0 ? 0.0 : min(1.0, d / v.distance);
      return (p[i] + v * t, v.direction);
    }
    d -= v.distance;
  }
  return (p.last, 0);
}


bool _intersect(Offset a, Offset b, Offset c, Offset d) {
  double cross(Offset o, Offset p, Offset q) =>
      (p.dx - o.dx) * (q.dy - o.dy) - (p.dy - o.dy) * (q.dx - o.dx);
  final d1 = cross(c, d, a), d2 = cross(c, d, b);
  final d3 = cross(a, b, c), d4 = cross(a, b, d);
  return (d1 > 0) != (d2 > 0) && (d3 > 0) != (d4 > 0);
}

// ponytail: sampled every 4px, not exact clipping; fine while zones are much bigger than 4px.
bool routeHits(List<Offset> route, bool Function(Offset) inside) {
  for (var i = 0; i + 1 < route.length; i++) {
    final v = route[i + 1] - route[i];
    final n = max(1, (v.distance / 4).ceil());
    for (var j = 0; j <= n; j++) {
      if (inside(route[i] + v * (j / n))) return true;
    }
  }
  return false;
}

/// A stretch of one line's segment that runs alongside other lines: route distances
/// (from stops[seg], along pathBetween(stops[seg], stops[seg+1])), the sideways shift of this
/// line's lane, and how many lines share the stretch.
typedef Lane = ({double from, double to, Offset shift, int shared});

/// Where lines run over the same stretch of track, gives each its own lane side by side
/// ([gap] apart, in line order) instead of drawing them on top of each other.
/// Result: (line, segment index) -> its shared stretches; anything not listed is unshared.
Map<(MetroLine, int), List<Lane>> laneLayout(List<MetroLine> lines, {double gap = 6}) {
  // Every straight piece of every segment's octilinear route, grouped by the infinite line it
  // lies on: direction class (0 horizontal, 1 vertical, 2 diagonal "\", 3 diagonal "/") and
  // that line's constant. t is the position along it (x, or y for vertical).
  final groups = <(int, int), List<(MetroLine, int seg, double ta, double tb, double s0, double len, Offset dir)>>{};
  for (final l in lines) {
    for (var i = 0; i + 1 < l.stops.length; i++) {
      final r = l.route(l.stops[i], l.stops[i + 1]);
      var s = 0.0;
      for (var j = 0; j + 1 < r.length; j++) {
        final a = r[j], v = r[j + 1] - a, len = v.distance;
        if (len > 0.5) {
          final d = v.dy.abs() < 1e-6 ? 0 : v.dx.abs() < 1e-6 ? 1 : (v.dx > 0) == (v.dy > 0) ? 2 : 3;
          final c = switch (d) { 0 => a.dy, 1 => a.dx, 2 => a.dy - a.dx, _ => a.dy + a.dx };
          final ta = d == 1 ? a.dy : a.dx, tb = d == 1 ? a.dy + v.dy : a.dx + v.dx;
          (groups[(d, (c * 100).round())] ??= []).add((l, i, ta, tb, s, len, v / len));
        }
        s += len;
      }
    }
  }
  final out = <(MetroLine, int), List<Lane>>{};
  for (final pieces in groups.values) {
    if (pieces.map((p) => p.$1).toSet().length < 2) continue;
    final cuts = {for (final p in pieces) ...[p.$3, p.$4]}.toList()..sort();
    for (var k = 0; k + 1 < cuts.length; k++) {
      final u = cuts[k], w = cuts[k + 1];
      if (w - u < 0.5) continue;
      final here = pieces.where((p) => min(p.$3, p.$4) <= u + 1e-6 && max(p.$3, p.$4) >= w - 1e-6).toList();
      final sharing = here.map((p) => p.$1).toSet().toList()..sort((a, b) => lines.indexOf(a).compareTo(lines.indexOf(b)));
      if (sharing.length < 2) continue;
      // Sides are taken from the first line's direction of travel here (not a fixed side per
      // direction), so lines running together through a corner keep their order: no crossing.
      final lead = here.firstWhere((p) => p.$1 == sharing.first).$7;
      final normal = Offset(-lead.dy, lead.dx);
      for (final (l, seg, ta, tb, s0, len, _) in here) {
        double s(double t) => s0 + (t - ta) / (tb - ta) * len;
        final slot = sharing.indexOf(l) - (sharing.length - 1) / 2;
        (out[(l, seg)] ??= []).add((
          from: min(s(u), s(w)),
          to: max(s(u), s(w)),
          shift: normal * (slot * gap),
          shared: sharing.length,
        ));
      }
    }
  }
  for (final lanes in out.values) {
    lanes.sort((a, b) => a.from.compareTo(b.from));
  }
  return out;
}

/// The point [back] px behind train [t] along the track it came by (where its carriages
/// ride): position and heading, plus its segment and distance from stops[seg] (for lanes).
/// Behind a terminus the train has just turned round at, the carriages fold back onto the
/// same track (the train reverses as a whole).
({Offset pos, double angle, int seg, double s}) trackBehind(Train t, double back) {
  final l = t.line, n = l.stops.length - 1; // number of segments
  var seg = t.seg, along = t.along - back;
  final dir = t.dir;
  for (var guard = 0; along < 0 && guard < 8; guard++) {
    var prev = dir == 1 ? seg - 1 : seg + 1; // the segment we came along
    if (l.loop) prev = (prev + n) % n;
    if (prev < 0 || prev >= n) {
      along = -along;
      break;
    }
    seg = prev;
    along += pathLength(l.route(l.stops[seg], l.stops[seg + 1]));
  }
  final from = dir == 1 ? l.stops[seg] : l.stops[seg + 1], to = dir == 1 ? l.stops[seg + 1] : l.stops[seg];
  final r = l.route(from, to), len = pathLength(r);
  along = along.clamp(0.0, len);
  final (p, angle) = pointAlong(r, along);
  return (pos: p, angle: angle, seg: seg, s: dir == 1 ? along : len - along);
}

/// The lane at route distance [s] of a segment, from [laneLayout]; null = unshared.
Lane? laneAt(List<Lane>? lanes, double s) =>
    lanes?.where((z) => s >= z.from - 1e-6 && s <= z.to + 1e-6).firstOrNull;

/// How far (px) a line takes to ease into or out of its lane, and round a lane's corner.
const laneEase = 12.0;

/// The sideways shift of a segment's track at route distance [s] (route length [len]): its
/// lane's shift averaged over ±[laneEase], so lines glide into and out of shared track
/// instead of stepping sideways. Trains use it too, so they ride exactly on the drawn lane.
/// Exact (the overlap of the window with each lane), so it is piecewise linear with knots
/// only at [laneKnots]: the track can be drawn through those few points.
Offset laneShift(List<Lane>? lanes, double s, double len) {
  if (lanes == null) return Offset.zero;
  var sum = Offset.zero;
  for (final z in lanes) {
    final (from, to) = _laneSpan(z, len);
    final overlap = min(to, s + laneEase) - max(from, s - laneEase);
    if (overlap > 0) sum += z.shift * overlap;
  }
  return sum / (2 * laneEase);
}

/// A lane that reaches a station runs on straight into it (its window never eases out there).
(double, double) _laneSpan(Lane z, double len) =>
    (z.from <= 1e-6 ? -laneEase : z.from, z.to >= len - 1e-6 ? len + laneEase : z.to);

/// Where [laneShift] bends: every lane edge ± [laneEase], within the segment.
Iterable<double> laneKnots(List<Lane> lanes, double len) sync* {
  for (final z in lanes) {
    final (from, to) = _laneSpan(z, len);
    for (final k in [from - laneEase, from + laneEase, to - laneEase, to + laneEase]) {
      if (k > 0 && k < len) yield k;
    }
  }
}

/// Distance along [route] to the point on it nearest [p], and the track's heading there.
(double, double) nearestAlong(List<Offset> route, Offset p) {
  var best = double.infinity, at = 0.0, heading = 0.0, run = 0.0;
  for (var i = 0; i + 1 < route.length; i++) {
    final a = route[i], ab = route[i + 1] - a;
    if (ab.distance == 0) continue;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / ab.distanceSquared).clamp(0.0, 1.0);
    final d = (p - (a + ab * t)).distance;
    if (d < best) {
      best = d;
      at = run + ab.distance * t;
      heading = ab.direction;
    }
    run += ab.distance;
  }
  return (at, heading);
}

double distToPolyline(Offset p, List<Offset> line) {
  var best = double.infinity;
  for (var i = 0; i + 1 < line.length; i++) {
    final a = line[i], ab = line[i + 1] - a;
    final t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / ab.distanceSquared;
    best = min(best, (p - (a + ab * t.clamp(0.0, 1.0))).distance);
  }
  return best;
}
