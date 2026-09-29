# init_tasks

A pure-Dart task scheduler for app initialization — declare dependencies
between tasks, run them in topological order with parallel levels.

## Quick start

```sh
dart pub add init_tasks
```

```dart
import 'package:init_tasks/init_tasks.dart';

class InitConfig extends InitTask {
  @override
  Future<void> run() async {
    // load remote config...
  }
}

class InitDatabase extends InitTask {
  @override
  Future<void> run() async {
    // open database...
  }
}

Future<void> main() async {
  final scheduler = InitScheduler()
    ..add(InitConfig())
    ..add(InitDatabase(), dependsOn: [InitConfig()]);

  await scheduler.run();
}
```

`dependsOn` takes task **instances**; identity is by `InitTask.id`
(defaults to the class name), so you never hand-write string ids.

## Annotation-driven wiring (recommended)

Annotate task classes and let `init_tasks_builder` generate the
wiring — you only declare *what depends on what*:

```dart
import 'package:init_tasks/init_tasks.dart';

part 'app_init.g.dart';

@Init()
class InitConfig extends InitTask {
  @override
  Future<void> run() async { /* ... */ }
}

@Init(dependsOn: [InitConfig]) // Type reference: typos are compile errors
class InitDatabase extends InitTask {
  @override
  Future<void> run() async { /* ... */ }
}

Future<void> main() => buildInitScheduler().run(); // generated
```

Run codegen with:

```sh
dart pub add --dev init_tasks_builder build_runner
dart run build_runner build
```

Rules for annotated classes:

- One scheduler per library (`buildInitScheduler()` is generated per library).
- Dependencies must be `@Init` classes in the same library, referenced by
  simple name.
- Each class needs an unnamed constructor with no required parameters.

## How scheduling works

- Tasks are grouped into levels via Kahn's algorithm; every task in a level
  starts after all tasks in the previous level finished.
- Tasks within one level run concurrently (`Future.wait`).
- `resolve()` returns the levels without running anything — handy for
  logging or validating the graph at startup.

## Failure semantics

- Graph problems fail **before anything runs**: `UnknownTaskException`
  (dependency never added), `DependencyCycleException` (with the cycle path),
  `DuplicateTaskException`.
- Default: the first task failure aborts the run with
  `InitTaskFailedException` (wraps the original error + stack trace).
  The error is reported immediately; already-started tasks are not cancelled.
- `run(continueOnError: true)`: every task whose dependencies succeeded
  still runs; dependents of failed tasks are skipped and reported via
  `InitObserver.onTaskSkipped`.
- Per-task `timeout` and `retries` on `add()`:

```dart
scheduler.add(
  FetchRemoteConfig(),
  timeout: const Duration(seconds: 10),
  retries: 2,
);
```

## Observing

```dart
await scheduler.run(); // Lifecycle logging is on by default outside release.
await scheduler.run(enableLogging: false); // Silence built-in logs.
// Or supply an InitObserver: onTaskStart / onTaskDone / onTaskError /
// onTaskRetry / onTaskSkipped
```

A custom `observer` replaces the built-in logger and receives events even when
`enableLogging: false`.

Release builds (`dart.vm.product: true`, including Flutter release) always
suppress built-in logs, even with `enableLogging: true` or an explicitly supplied
`PrintInitObserver`. Custom observers still receive lifecycle events.

Observer callback exceptions are ignored so they cannot change task outcomes
or retries. Handle logging/reporting errors inside your observer if needed.
