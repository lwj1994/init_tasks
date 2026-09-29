---
name: "init-tasks"
description: "Schedule Dart app-initialization tasks with dependencies: annotate task classes with @Init and generate the wiring with init_tasks_builder, or wire an InitScheduler manually. Use when the user wants ordered init tasks, startup sequencing, or dependency-ordered work in Dart/Flutter."
---

# init_tasks

## Purpose

Declare app-initialization tasks and their dependencies in Dart, then run
them in topological order with independent tasks in parallel. Two APIs:
annotation-driven codegen (preferred) and manual scheduler wiring.

## Workflow

### 1. Prefer the annotation API

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

Setup: add `init_tasks_builder` to `dev_dependencies`, then run
`dart run build_runner build` in that package. After changing annotations,
re-run codegen and keep the checked-in `.g.dart` in sync (CI verifies this).

### 2. Manual API (dynamic tasks only)

```dart
final scheduler = InitScheduler()
  ..add(InitConfig())
  ..add(InitDatabase(), dependsOn: [InitConfig()]); // instances; identity by InitTask.id

await scheduler.run();
```

## Rules

- `@Init` classes: must not be abstract; must declare an unnamed
  constructor with no required parameters.
- `dependsOn` entries must be `@Init` classes in the same library,
  referenced by simple (unprefixed) name.
- One `buildInitScheduler()` per library.
- Scheduling: Kahn's algorithm groups tasks into levels; a level starts
  only after the previous level finished; tasks within a level run
  concurrently via `Future.wait`.
- `resolve()` returns the levels without running anything — use it to
  validate or log the plan at startup.
- Errors are typed and all extend `InitException`:
  `UnknownTaskException`, `DependencyCycleException` (carries the cycle
  path), `DuplicateTaskException`, `InitTaskFailedException` (wraps the
  original error + stack trace), `DependencyFailedException`. Graph errors
  throw before anything runs.
- Default: the first task failure aborts the run. With
  `run(continueOnError: true)`, every task whose dependencies succeeded
  still runs; dependents of failed tasks are skipped and reported via
  `InitObserver.onTaskSkipped`.
- Per-task `timeout` / `retries` on `add()`. Timeout does NOT cancel the
  underlying Future: the attempt is reported as failed, and a retry may
  start while the old attempt still runs in the background.
- Observe with `InitObserver` (all hooks default to no-ops) or the
  print-based `PrintInitObserver`.

## Operating rules

1. Never hand-write dependency wiring the generator can produce. If the
   task set is static, use `@Init`.
2. Never use string ids for dependencies in the annotation API —
   `dependsOn` takes types.
3. Quote the exact exception type when reporting failures; never invent
   error names outside the typed list in Rules above.
