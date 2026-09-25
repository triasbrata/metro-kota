import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metro_kota/city.dart';
import 'package:metro_kota/game.dart';

import 'harness.dart';

// Regression: at some window sizes (e.g. tablet split-screen) float rounding made the
// camera clamp's lower bound exceed its upper bound, throwing in build = blank screen.
void main() {
  for (final (size, dpr) in [(const Size(1589, 2136), 2.2), (const Size(3200, 2136), 2.0), (const Size(2340, 1080), 2.625)]) {
    for (final city in cities) {
      testWidgets('${city.name} opens at ${size.width}x${size.height} @$dpr', (tester) async {
        await boot(tester, () => CityScene(city), size: size, dpr: dpr);
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
