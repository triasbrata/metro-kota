import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      responseDataCallback: (data) async {
        final p = data!['perf'] as Map<String, dynamic>;
        // ignore: avoid_print
        print('PERF ${[
          for (final k in [
            'average_frame_build_time_millis',
            '90th_percentile_frame_build_time_millis',
            'worst_frame_build_time_millis',
            'average_frame_rasterizer_time_millis',
            '90th_percentile_frame_rasterizer_time_millis',
            'worst_frame_rasterizer_time_millis',
            'frame_count',
            'missed_frame_build_budget_count',
            'missed_frame_rasterizer_budget_count',
          ])
            '$k=${p[k]}'
        ].join('\n')}');
      },
    );
