import 'exceptions.dart';
import 'task.dart';

/// Observes a [InitScheduler] run. All methods default to no-ops.
///
/// Callback exceptions are ignored by the scheduler so observation cannot
/// change task outcomes or retries. Handle errors inside callbacks if needed.
class InitObserver {
  const InitObserver();

  /// Called right before a task starts (each attempt, including retries,
  /// triggers [onTaskRetry] instead of a second [onTaskStart]).
  void onTaskStart(InitTask task) {}

  /// Called when a task finished successfully.
  void onTaskDone(InitTask task, Duration elapsed) {}

  /// Called when a task failed its final attempt.
  void onTaskError(InitTask task, Object error, StackTrace stackTrace) {}

  /// Called before a retry attempt. [attempt] is 1-based.
  void onTaskRetry(InitTask task, int attempt) {}

  /// Called when a task is skipped because a dependency failed.
  /// Only happens with `continueOnError: true`.
  void onTaskSkipped(InitTask task, DependencyFailedException reason) {}
}

/// A [InitObserver] that prints lifecycle events. Handy for debugging init.
/// Always silent in release builds (`dart.vm.product`), including when supplied
/// explicitly to the scheduler.
class PrintInitObserver extends InitObserver {
  static const _isReleaseMode = bool.fromEnvironment('dart.vm.product');

  const PrintInitObserver();

  @override
  void onTaskStart(InitTask task) {
    if (!_isReleaseMode) print('[init] start ${task.id}');
  }

  @override
  void onTaskDone(InitTask task, Duration elapsed) {
    if (!_isReleaseMode) {
      print('[init] done  ${task.id} in ${elapsed.inMilliseconds}ms');
    }
  }

  @override
  void onTaskError(InitTask task, Object error, StackTrace stackTrace) {
    if (!_isReleaseMode) print('[init] error ${task.id}: $error');
  }

  @override
  void onTaskRetry(InitTask task, int attempt) {
    if (!_isReleaseMode) print('[init] retry ${task.id} (attempt $attempt)');
  }

  @override
  void onTaskSkipped(InitTask task, DependencyFailedException reason) {
    if (!_isReleaseMode) print('[init] skip  ${task.id}: ${reason.message}');
  }
}
