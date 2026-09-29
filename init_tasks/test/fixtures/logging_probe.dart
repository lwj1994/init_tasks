import 'package:init_tasks/init_tasks.dart';

Future<void> main() async {
  final counter = _CountingObserver();
  for (final observer in [null, const PrintInitObserver(), counter]) {
    var attempts = 0;
    final failed = _Task('failed', () => throw StateError('failed'));
    final scheduler = InitScheduler()
      ..add(
          _Task('flaky', () {
            if (++attempts == 1) throw StateError('retry');
          }),
          retries: 1)
      ..add(failed)
      ..add(_Task('skipped', () => throw StateError('must not run')),
          dependsOn: [failed]);
    await scheduler.run(observer: observer, continueOnError: true);
    if (attempts != 2) throw StateError('Expected two attempts');
  }
  if (counter.events != 6) throw StateError('Observer events were suppressed');
  print('complete');
}

class _Task extends InitTask {
  @override
  final String id;
  final void Function() action;

  _Task(this.id, this.action);

  @override
  void run() => action();
}

class _CountingObserver extends InitObserver {
  int events = 0;

  @override
  void onTaskStart(InitTask task) => events++;

  @override
  void onTaskDone(InitTask task, Duration elapsed) => events++;

  @override
  void onTaskError(InitTask task, Object error, StackTrace stackTrace) =>
      events++;

  @override
  void onTaskRetry(InitTask task, int attempt) => events++;

  @override
  void onTaskSkipped(InitTask task, DependencyFailedException reason) =>
      events++;
}
