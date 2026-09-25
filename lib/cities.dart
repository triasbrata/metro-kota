import 'dart:ui';

/// A river (open polyline) or sea (closed polygon, filled) on the city map.
class Water {
  const Water(this.width, this.points, {this.sea = false});
  final double width;
  final List<Offset> points;
  final bool sea;

  List<Offset> get outline => sea ? [...points, points.first] : points;
}

class City {
  const City(this.name, this.blurb, this.water,
      {this.goal = (money: 180000, stations: 10, riders: 500),
      this.normalFare = 350,
      this.startMoney = 24000,
      this.bridgeCost = 6000,
      this.demand = 1.0});
  final String name;
  final String blurb;
  final List<Water> water;

  /// Achievements that clear the city, with no time limit: total fare income earned here,
  /// stations connected to the network, and riders delivered.
  final ({int money, int stations, int riders}) goal;

  /// What locals find a normal fare (purchasing power). Above it, riders lose patience faster.
  final int normalFare;
  final int startMoney;
  final int bridgeCost; // tunnel surcharge for track across water
  final double demand; // passenger spawn multiplier
}

// Played in order, easiest first. Stylised maps on a 1000x620 world:
// the recognisable feature of each city, not real geography.
// Goals get harder city by city; money ≈ riders × the city's normal fare.
const cities = [
  City(
    'Medan',
    'Sungai Deli dan Babura bertemu di tengah kota.',
    [
      Water(28, [Offset(600, 0), Offset(560, 250), Offset(620, 420), Offset(580, 620)]),
      Water(22, [Offset(350, 620), Offset(420, 400), Offset(560, 250)]),
    ],
  ),
  City(
    'Semarang',
    'Pantai utara dengan Banjir Kanal Barat dan Timur.',
    [
      Water(0, [Offset(0, 0), Offset(1000, 0), Offset(1000, 80), Offset(700, 95), Offset(400, 75), Offset(0, 95)], sea: true),
      Water(26, [Offset(380, 620), Offset(360, 400), Offset(330, 80)]),
      Water(26, [Offset(700, 620), Offset(680, 350), Offset(720, 90)]),
    ],
    goal: (money: 185000, stations: 11, riders: 600),
    normalFare: 300,
  ),
  City(
    'Bandung',
    'Kota kembang di cekungan: sungai kecil, terowongan murah, modal tipis.',
    [
      Water(20, [Offset(520, 0), Offset(500, 200), Offset(540, 400), Offset(480, 620)]),
      Water(30, [Offset(0, 560), Offset(400, 540), Offset(700, 570), Offset(1000, 545)]),
    ],
    goal: (money: 240000, stations: 12, riders: 700),
    startMoney: 18000,
    bridgeCost: 3600,
    demand: 1.1,
  ),
  City(
    'Makassar',
    'Pantai Losari di barat, Sungai Jeneberang di selatan.',
    [
      Water(0, [Offset(0, 0), Offset(200, 0), Offset(170, 200), Offset(220, 350), Offset(150, 620), Offset(0, 620)], sea: true),
      Water(30, [Offset(1000, 520), Offset(700, 540), Offset(450, 500), Offset(180, 520)]),
    ],
    goal: (money: 231000, stations: 13, riders: 750),
    normalFare: 300,
    startMoney: 26000,
  ),
  City(
    'Surabaya',
    'Selat Madura di utara dan timur, Kali Mas mengalir ke pelabuhan.',
    [
      Water(0, [Offset(0, 0), Offset(1000, 0), Offset(1000, 620), Offset(900, 620), Offset(880, 400), Offset(850, 150), Offset(700, 90), Offset(400, 70), Offset(0, 90)], sea: true),
      Water(28, [Offset(380, 620), Offset(420, 420), Offset(470, 250), Offset(450, 75)]),
    ],
    goal: (money: 343000, stations: 14, riders: 850),
    normalFare: 400,
  ),
  City(
    'Palembang',
    'Sungai Musi yang lebar membelah kota. Terowongan di bawahnya mahal.',
    [
      Water(60, [Offset(0, 330), Offset(300, 300), Offset(550, 340), Offset(800, 290), Offset(1000, 310)]),
      Water(28, [Offset(450, 620), Offset(480, 450), Offset(520, 335)]),
    ],
    goal: (money: 283000, stations: 15, riders: 950),
    normalFare: 300,
    startMoney: 32000,
    bridgeCost: 10000,
  ),
  City(
    'Jakarta',
    'Teluk Jakarta di utara, Ciliwung & kanal membelah kota. Penumpang paling ramai dan paling mampu bayar.',
    [
      Water(0, [Offset(0, 0), Offset(1000, 0), Offset(1000, 70), Offset(800, 95), Offset(620, 80), Offset(450, 105), Offset(250, 85), Offset(0, 100)], sea: true),
      Water(30, [Offset(560, 620), Offset(540, 480), Offset(500, 380), Offset(510, 250), Offset(470, 90)]),
      Water(22, [Offset(150, 620), Offset(180, 400), Offset(230, 250), Offset(200, 90)]),
      Water(22, [Offset(900, 620), Offset(860, 400), Offset(820, 90)]),
    ],
    goal: (money: 536000, stations: 18, riders: 1100),
    normalFare: 500,
    startMoney: 28000,
    demand: 1.3,
  ),
];
