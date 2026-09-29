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

  for (final lateFailure in [false, true]) {
    test('fails before a pending sibling completes (lateFailure: $lateFailure)',
        () async {
      final log = <String>[];
      final release = Completer<void>();
      final siblingFinished = Completer<void>();
      final boom =
          _Probe('boom', log, behavior: () => throw StateError('first'));
      final scheduler = InitScheduler()
        ..add(boom)
        ..add(_Probe('pending', log, behavior: () async {
          await release.future;
          if (lateFailure) throw StateError('late');
        }))
        ..add(_Probe('after', log), dependsOn: [boom]);
      final observer = _RecordingObserver(
        onDone: (task, _) {
          if (task.id == 'pending') siblingFinished.complete();
        },
        onError: (task, _, __) {
          if (task.id == 'pending') siblingFinished.complete();
        },
      );

      try {
        await expectLater(
          scheduler.run(observer: observer).timeout(const Duration(seconds: 2)),
          throwsA(isA<InitTaskFailedException>()
              .having((e) => e.taskId, 'taskId', 'boom')),
        );
        expect(siblingFinished.isCompleted, isFalse);
        expect(log, isNot(contains('start:after')));
      } finally {
        release.complete();
        await siblingFinished.future;
      }
    });
  }

  for (final continueOnError in [false, true]) {
    test('observer errors do not rerun success ($continueOnError)', () async {
      final log = <String>[];
      final task = _Probe('success', log);
      final observer = _ThrowingObserver();
      await (InitScheduler()
            ..add(task, retries: 2)
            ..add(_Probe('child', log), dependsOn: [task]))
          .run(observer: observer, continueOnError: continueOnError);

      expect(log, ['start:success', 'end:success', 'start:child', 'end:child']);
      expect(observer.events,
          ['start:success', 'done:success', 'start:child', 'done:child']);
    });
  }

  test('observer errors do not interrupt retries or mask the task error',
      () async {
    final log = <String>[];
    final original = StateError('task failed');
    final observer = _ThrowingObserver();
    final scheduler = InitScheduler()
      ..add(_Probe('boom', log, behavior: () => throw original), retries: 1);

    await expectLater(
      scheduler.run(observer: observer),
      throwsA(isA<InitTaskFailedException>()
          .having((e) => e.error, 'error', same(original))),
    );
    expect(log, ['start:boom', 'start:boom']);
    expect(observer.events, ['start:boom', 'retry:boom', 'error:boom']);
  });

  test('observer errors do not interrupt skipping or independent branches',
      () async {
    final log = <String>[];
    final observer = _ThrowingObserver();
    final boom =
        _Probe('boom', log, behavior: () => throw StateError('failed'));
    final skipped = _Probe('skipped', log);
    final independent = _Probe('independent', log);
    final scheduler = InitScheduler()
      ..add(boom)
      ..add(independent)
      ..add(skipped, dependsOn: [boom])
      ..add(_Probe('descendant', log), dependsOn: [skipped])
      ..add(_Probe('child', log), dependsOn: [independent]);

    await scheduler.run(observer: observer, continueOnError: true);
    expect(log, contains('end:child'));
    expect(log, isNot(contains('start:skipped')));
    expect(log, isNot(contains('start:descendant')));
    expect(observer.events,
        containsAll(['error:boom', 'skip:skipped', 'skip:descendant']));
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

  test('lifecycle logging is enabled by default', () async {
    final messages = <String>[];
    await runZoned(
      () => (InitScheduler()..add(_Probe('a', []))).run(),
      zoneSpecification: ZoneSpecification(
        print: (_, __, ___, message) => messages.add(message),
      ),
    );
    expect(messages, hasLength(2));
    expect(messages.first, '[init] start a');
    expect(messages.last, startsWith('[init] done  a in '));
  });

  test('enableLogging false silences built-in logs without skipping tasks',
      () async {
    final messages = <String>[];
    final log = <String>[];
    await runZoned(
      () => (InitScheduler()..add(_Probe('a', log))).run(enableLogging: false),
      zoneSpecification: ZoneSpecification(
        print: (_, __, ___, message) => messages.add(message),
      ),
    );
    expect(messages, isEmpty);
    expect(log, ['start:a', 'end:a']);
  });

  for (final enableLogging in [false, true]) {
    test('custom observer replaces built-in logs ($enableLogging)', () async {
      final messages = <String>[];
      final events = <String>[];
      await runZoned(
        () => (InitScheduler()..add(_Probe('a', []))).run(
          enableLogging: enableLogging,
          observer: _RecordingObserver(
            onStart: (task) => events.add('start:${task.id}'),
            onDone: (task, _) => events.add('done:${task.id}'),
          ),
        ),
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, message) => messages.add(message),
        ),
      );
      expect(messages, isEmpty);
      expect(events, ['start:a', 'done:a']);
    });
  }
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
  final void Function(InitTask, Object, StackTrace)? onError;

  _RecordingObserver({this.onStart, this.onDone, this.onSkipped, this.onError});

  @override
  void onTaskStart(InitTask task) => onStart?.call(task);

  @override
  void onTaskDone(InitTask task, Duration e) => onDone?.call(task, e);

  @override
  void onTaskSkipped(InitTask task, DependencyFailedException reason) =>
      onSkipped?.call(task.id);

  @override
  void onTaskError(InitTask task, Object error, StackTrace stackTrace) =>
      onError?.call(task, error, stackTrace);
}

class _ThrowingObserver extends InitObserver {
  final events = <String>[];

  void _record(String event, InitTask task) {
    events.add('$event:${task.id}');
    throw StateError('observer failed');
  }

  @override
  void onTaskStart(InitTask task) => _record('start', task);

  @override
  void onTaskDone(InitTask task, Duration elapsed) => _record('done', task);

  @override
  void onTaskRetry(InitTask task, int attempt) => _record('retry', task);

  @override
  void onTaskError(InitTask task, Object error, StackTrace stackTrace) =>
      _record('error', task);

  @override
  void onTaskSkipped(InitTask task, DependencyFailedException reason) =>
      _record('skip', task);
}
