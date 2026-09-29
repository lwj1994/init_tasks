import 'dart:async';

import 'package:init_tasks/init_tasks.dart';
import 'package:test/test.dart';

class _Probe extends InitTask {
  final List<String> log;
  final Duration delay;
  final String _id;
  final FutureOr<void> Function()? behavior;

  _Probe(this._id, this.log, {this.delay = Duration.zero, this.behavior});

  @override
  String get id => _id;

  @override
  FutureOr<void> run() async {
    log.add('start:$id');
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    await behavior?.call();
    log.add('end:$id');
  }
}

void main() {
  test('runs tasks in topological order', () async {
    final log = <String>[];
    final scheduler = InitScheduler()
      ..add(_Probe('config', log))
      ..add(_Probe('db', log), dependsOn: [_Probe('config', log)])
      ..add(_Probe('ui', log),
          dependsOn: [_Probe('db', log), _Probe('config', log)]);

    // NOTE: dependsOn takes instances; identity is by id, so fresh
    // instances with the same id are fine.
    await scheduler.run();

    final order = log.where((e) => e.startsWith('start:')).toList();
    expect(order, ['start:config', 'start:db', 'start:ui']);
  });

  test('independent tasks run concurrently', () async {
    final log = <String>[];
    final scheduler = InitScheduler()
      ..add(_Probe('a', log, delay: const Duration(milliseconds: 200)))
      ..add(_Probe('b', log, delay: const Duration(milliseconds: 200)));

    final stopwatch = Stopwatch()..start();
    await scheduler.run();
    stopwatch.stop();

    // Sequential would take >= 400ms; concurrent takes ~200ms.
    expect(stopwatch.elapsedMilliseconds, lessThan(350));
    expect(log.where((e) => e.startsWith('start:')), hasLength(2));
  });

  test('levels are resolved deterministically', () {
    final log = <String>[];
    final config = _Probe('config', log);
    final db = _Probe('db', log);
    final cache = _Probe('cache', log);
    final ui = _Probe('ui', log);
    final scheduler = InitScheduler()
      ..add(config)
      ..add(db, dependsOn: [config])
      ..add(cache, dependsOn: [config])
      ..add(ui, dependsOn: [db, cache]);

    final levels = scheduler.resolve();
    expect(levels.map((l) => l.map((t) => t.id).toList()).toList(), [
      ['config'],
      ['db', 'cache'],
      ['ui'],
    ]);
  });

  test('cycle throws DependencyCycleException with the path', () {
    final log = <String>[];
    final a = _Probe('a', log);
    final b = _Probe('b', log);
    final scheduler = InitScheduler()
      ..add(a, dependsOn: [b])
      ..add(b, dependsOn: [a]);

    expect(
      scheduler.resolve,
      throwsA(isA<DependencyCycleException>().having(
        (e) => e.cycle.join('->'),
        'cycle',
        contains('a->b->a'),
      )),
    );
  });

  test('self-dependency is a cycle', () {
    final log = <String>[];
    final a = _Probe('a', log);
    final scheduler = InitScheduler()..add(a, dependsOn: [a]);

    expect(scheduler.run, throwsA(isA<DependencyCycleException>()));
  });

  test('unknown dependency throws before running', () async {
    final log = <String>[];
    final scheduler = InitScheduler()
      ..add(_Probe('ui', log), dependsOn: [_Probe('db', log)]);

    expect(scheduler.run, throwsA(isA<UnknownTaskException>()));
    expect(log, isEmpty, reason: 'nothing should run on graph errors');
  });

  test('duplicate id throws DuplicateTaskException', () {
    final log = <String>[];
    final scheduler = InitScheduler()..add(_Probe('a', log));
    expect(
      () => scheduler.add(_Probe('a', log)),
      throwsA(isA<DuplicateTaskException>()),
    );
  });

  test('task failure fails fast with InitTaskFailedException', () async {
    final log = <String>[];
    final scheduler = InitScheduler()
      ..add(_Probe('boom', log, behavior: () => throw StateError('kaput')))
      ..add(_Probe('after', log), dependsOn: [_Probe('boom', log)]);

    await expectLater(
      scheduler.run(),
      throwsA(isA<InitTaskFailedException>()
          .having((e) => e.taskId, 'taskId', 'boom')
          .having((e) => e.error, 'error', isStateError)),
    );
    expect(log, contains('start:boom'));
    expect(log.any((e) => e == 'start:after'), isFalse);
  });

  test('continueOnError skips dependents and reports them', () async {
    final log = <String>[];
    final skipped = <String>[];
    final scheduler = InitScheduler()
      ..add(_Probe('boom', log, behavior: () => throw StateError('kaput')))
      ..add(_Probe('after', log), dependsOn: [_Probe('boom', log)])
      ..add(_Probe('independent', log));

    final observer = _RecordingObserver(onSkipped: skipped.add);
    await scheduler.run(continueOnError: true, observer: observer);

    expect(log, contains('start:independent'));
    expect(log, contains('end:independent'));
    expect(log.any((e) => e == 'start:after'), isFalse);
    expect(skipped, ['after']);
  });

  test('timeout fails the task', () async {
    final log = <String>[];
    final scheduler = InitScheduler()
      ..add(
        _Probe('slow', log, delay: const Duration(milliseconds: 300)),
        timeout: const Duration(milliseconds: 50),
      );

    await expectLater(
      scheduler.run(),
      throwsA(isA<InitTaskFailedException>().having(
        (e) => e.error,
        'error',
        isA<TimeoutException>(),
      )),
    );
  });

  test('retries re-run a flaky task', () async {
    final log = <String>[];
    var attempts = 0;
    final scheduler = InitScheduler()
      ..add(
        _Probe('flaky', log, behavior: () {
          if (++attempts < 3) throw StateError('not yet');
        }),
        retries: 2,
      );

    await scheduler.run();
    expect(attempts, 3);
    expect(log, contains('end:flaky'));
  });

  test('retries exhausted throws', () async {
    final log = <String>[];
    var attempts = 0;
    final scheduler = InitScheduler()
      ..add(
        _Probe('always-fails', log, behavior: () {
          attempts++;
          throw StateError('nope');
        }),
        retries: 1,
      );

    await expectLater(scheduler.run(), throwsA(isA<InitTaskFailedException>()));
    expect(attempts, 2);
  });

  test('sync tasks are supported', () async {
    var ran = false;
    final task = _SyncTask(() => ran = true);
    await (InitScheduler()..add(task)).run();
    expect(ran, isTrue);
  });

  test('observer receives lifecycle events', () async {
    final log = <String>[];
    final events = <String>[];
    final scheduler = InitScheduler()
      ..add(_Probe('a', log))
      ..add(_Probe('b', log), dependsOn: [_Probe('a', log)]);

    await scheduler.run(
        observer: _RecordingObserver(
      onStart: (t) => events.add('start:${t.id}'),
      onDone: (t, _) => events.add('done:${t.id}'),
    ));

    expect(events, ['start:a', 'done:a', 'start:b', 'done:b']);
  });
}

class _SyncTask extends InitTask {
  final void Function() fn;
  _SyncTask(this.fn);

  @override
  void run() => fn();
}

class _RecordingObserver extends InitObserver {
  final void Function(InitTask)? onStart;
  final void Function(InitTask, Duration)? onDone;
  final void Function(String)? onSkipped;

  _RecordingObserver({this.onStart, this.onDone, this.onSkipped});

  @override
  void onTaskStart(InitTask task) => onStart?.call(task);

  @override
  void onTaskDone(InitTask task, Duration e) => onDone?.call(task, e);

  @override
  void onTaskSkipped(InitTask task, DependencyFailedException reason) =>
      onSkipped?.call(task.id);
}
