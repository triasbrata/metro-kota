// Frame-time benchmark on a busy city. Run in profile mode on a real device/desktop:
//   flutter drive --profile --driver=test_driver/perf_driver.dart --target=integration_test/perf_test.dart -d <device>
// Prints average/worst build and raster times and the share of missed frames.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:metro_kota/app.dart';
import 'package:metro_kota/city.dart';
import 'package:metro_kota/game.dart';
import 'package:metro_kota/settings.dart';
import 'package:metro_kota/sfx.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('busy Jakarta at 2x', (tester) async {
    await Sounds.init(); // real audio too: its cost counts (machines without a device run silent)
    // ignore: avoid_print
    print('SOUND ready=${Sounds.ready}');
    final city = cities.last;
    await tester.pumpWidget(MetroKota(home: () => CityScene(city)));
    await tester.pump();
    final st = tester.state<App>(find.byType(MetroKota)).top as CityScene;
    final g = Game(city, seed: 7);
    for (var i = 0; i < 20; i++) {
      g.spawnStation();
    }
    g.money = 1 << 30;
    // Lines through nearby stations, 2 trains each; one loop.
    final free = [...g.stations];
    while (free.length >= 3 && g.nextColor != null) {
      final chain = [free.removeAt(0)];
      while (chain.length < 4 && free.isNotEmpty) {
        free.sort((a, b) => (a.pos - chain.last.pos).distance.compareTo((b.pos - chain.last.pos).distance));
        chain.add(free.removeAt(0));
      }
      final l = g.createLine(chain[0], chain[1]);
      if (l == null) continue;
      for (final s in chain.skip(2)) {
        g.extend(l, s, atHead: false);
      }
      if (g.lines.length == 1) g.closeLoop(l);
      g.addTrain(l);
    }
    g.spawnZone();
    g.startFestival();
    g.popups.clear();
    st.game = g;
    st.speed = 2.0;
    Settings.showFps = true;
    await tester.pump();

    await binding.watchPerformance(() async {
      await Future<void>.delayed(const Duration(seconds: 12));
    }, reportKey: 'perf');
    // ignore: avoid_print
    print('lines=${g.lines.length} trains=${g.trainCount} stations=${g.stations.length} delivered=${g.delivered}');
  });
}
