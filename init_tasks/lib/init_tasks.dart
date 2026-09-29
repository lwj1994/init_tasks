/// A pure-Dart task scheduler for app initialization and similar
/// "run these things in dependency order" problems.
///
/// Tasks are [InitTask]s added to a [InitScheduler] with explicit dependencies.
/// [InitScheduler.run] executes them level by level in topological order,
/// running independent tasks concurrently.
///
/// For annotation-driven wiring, annotate task classes with [Init] and use
/// `init_tasks_builder` to generate `buildInitScheduler()`.
library;

export 'src/exceptions.dart';
export 'src/observer.dart';
export 'src/scheduler.dart';
export 'src/task.dart';
