import 'package:init_tasks_example/app_init.dart';

Future<void> main() async {
  final scheduler = buildInitScheduler();

  print('Plan:');
  for (final level in scheduler.resolve()) {
    print('  [${level.map((t) => t.id).join(', ')}]');
  }

  print('Running:');
  final stopwatch = Stopwatch()..start();
  await scheduler.run();
  stopwatch.stop();
  print('All init tasks done in ${stopwatch.elapsedMilliseconds}ms.');
}
