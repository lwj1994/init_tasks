import 'dart:async';

import 'exceptions.dart';
import 'observer.dart';
import 'task.dart';

/// Schedules [InitTask]s as a dependency graph.
///
/// Typical use — app initialization:
///
/// ```dart
/// final scheduler = InitScheduler()
///   ..add(InitConfig())
///   ..add(InitDatabase(), dependsOn: [InitConfig()])
///   ..add(InitCache(), dependsOn: [InitConfig()]);
///
/// await scheduler.run(); // InitDatabase and InitCache run concurrently
/// ```
///
/// [run] executes tasks level by level in topological order: every task in
/// a level starts only after all tasks in the previous level finished, and
/// tasks within one level run concurrently via [Future.wait].
class InitScheduler {
  final Map<String, InitTask> _tasks = {};
  final Map<String, Set<String>> _dependencies = {};
  final Map<String, Duration> _timeouts = {};
  final Map<String, int> _retries = {};

  /// All added tasks, in insertion order.
  List<InitTask> get tasks => List.unmodifiable(_tasks.values);

  /// Adds [task] to the scheduler.
  ///
  /// [dependsOn] lists tasks that must finish before [task] runs.
  /// [timeout] fails a single attempt if it takes longer than [timeout].
  /// [retries] re-runs a failed task this many extra times before giving up.
  ///
  /// Throws [DuplicateTaskException] if a task with the same id was added.
  /// Dependencies may be added before or after [task]; unknown ids are
  /// reported by [resolve]/[run] via [UnknownTaskException].
  void add(
    InitTask task, {
    List<InitTask> dependsOn = const [],
    Duration? timeout,
    int retries = 0,
  }) {
    if (retries < 0) {
      throw ArgumentError.value(retries, 'retries', 'must be >= 0');
    }
    if (_tasks.containsKey(task.id)) {
      throw DuplicateTaskException(task.id);
    }
    _tasks[task.id] = task;
    _dependencies[task.id] = {for (final dep in dependsOn) dep.id};
    if (timeout != null) _timeouts[task.id] = timeout;
    _retries[task.id] = retries;
  }

  /// Groups tasks into concurrently-runnable levels, in dependency order.
  ///
  /// Throws [UnknownTaskException] if a task depends on a task that was
  /// never added, [DependencyCycleException] if the graph contains a cycle.
  /// Safe to call before [run] to validate a graph without executing it.
  List<List<InitTask>> resolve() {
    for (final entry in _dependencies.entries) {
      for (final depId in entry.value) {
        if (!_tasks.containsKey(depId)) {
          throw UnknownTaskException(
            taskId: entry.key,
            dependencyId: depId,
          );
        }
      }
    }

    final indegree = <String, int>{for (final id in _tasks.keys) id: 0};
    final dependents = <String, List<String>>{
      for (final id in _tasks.keys) id: <String>[],
    };
    for (final entry in _dependencies.entries) {
      for (final depId in entry.value) {
        indegree[entry.key] = indegree[entry.key]! + 1;
        dependents[depId]!.add(entry.key);
      }
    }

    // Kahn's algorithm. Insertion order is preserved within a level,
    // so output is deterministic for the same insertion sequence.
    final levels = <List<InitTask>>[];
    var ready = [
      for (final id in _tasks.keys)
        if (indegree[id] == 0) id,
    ];
    var scheduled = 0;
    while (ready.isNotEmpty) {
      levels.add([for (final id in ready) _tasks[id]!]);
      scheduled += ready.length;
      final next = <String>[];
      for (final id in ready) {
        for (final dependent in dependents[id]!) {
          indegree[dependent] = indegree[dependent]! - 1;
          if (indegree[dependent] == 0) next.add(dependent);
        }
      }
      ready = next;
    }

    if (scheduled < _tasks.length) {
      throw DependencyCycleException(_findCycle());
    }
    return levels;
  }

  /// Runs all tasks and completes when every task finished.
  ///
  /// Independent tasks within a level run concurrently. By default the
  /// first failure aborts the run with [InitTaskFailedException]; pass
  /// [continueOnError] to instead run every task whose dependencies
  /// succeeded and skip the rest (reported via [InitObserver.onTaskSkipped]).
  /// Already-started tasks are not cancelled when a failure is reported.
  ///
  /// When no [observer] is supplied, [enableLogging] enables a
  /// [PrintInitObserver] by default. Set it to false to silence built-in logs.
  /// Built-in logs are always disabled in release builds (`dart.vm.product`).
  /// A supplied [observer] replaces the built-in logger and is always notified.
  ///
  /// Graph problems ([UnknownTaskException], [DependencyCycleException]) are
  /// thrown before any task runs.
  Future<void> run({
    InitObserver? observer,
    bool continueOnError = false,
    bool enableLogging = true,
  }) async {
    final levels = resolve();
    final effectiveObserver =
        observer ?? (enableLogging ? const PrintInitObserver() : null);
    final failed = <String>{};
    for (final level in levels) {
      await Future.wait(level.map((task) async {
        final failedDep = _firstFailedDependency(task.id, failed);
        if (failedDep != null) {
          failed.add(task.id);
          _notify(() => effectiveObserver?.onTaskSkipped(
                task,
                DependencyFailedException(task.id, failedDep),
              ));
          return;
        }
        try {
          await _runTask(task, effectiveObserver);
        } catch (_) {
          failed.add(task.id);
          if (!continueOnError) rethrow;
        }
      }), eagerError: !continueOnError);
    }
  }

  String? _firstFailedDependency(String taskId, Set<String> failed) {
    for (final depId in _dependencies[taskId]!) {
      if (failed.contains(depId)) return depId;
    }
    return null;
  }

  Future<void> _runTask(InitTask task, InitObserver? observer) async {
    final timeout = _timeouts[task.id];
    final maxRetries = _retries[task.id] ?? 0;
    _notify(() => observer?.onTaskStart(task));
    final stopwatch = Stopwatch()..start();
    var attempt = 0;
    while (true) {
      try {
        final future = Future.sync(task.run);
        await (timeout == null ? future : future.timeout(timeout));
      } catch (error, stackTrace) {
        if (attempt >= maxRetries) {
          _notify(() => observer?.onTaskError(task, error, stackTrace));
          throw InitTaskFailedException(task.id, error, stackTrace);
        }
        attempt++;
        _notify(() => observer?.onTaskRetry(task, attempt));
        continue;
      }
      _notify(() => observer?.onTaskDone(task, stopwatch.elapsed));
      return;
    }
  }

  void _notify(void Function() callback) {
    try {
      callback();
    } catch (_) {
      // Observers are best-effort: their errors must not change task outcomes.
    }
  }

  /// Finds one concrete cycle for the error message via DFS.
  List<String> _findCycle() {
    final visiting = <String>[];
    final visited = <String>{};
    List<String>? cycle;

    void dfs(String id) {
      if (cycle != null) return;
      final loopStart = visiting.indexOf(id);
      if (loopStart >= 0) {
        cycle = [...visiting.sublist(loopStart), id];
        return;
      }
      if (!visited.add(id)) return;
      visiting.add(id);
      for (final depId in _dependencies[id]!) {
        dfs(depId);
      }
      visiting.removeLast();
    }

    for (final id in _tasks.keys) {
      dfs(id);
      if (cycle != null) break;
    }
    return cycle ?? [];
  }
}
