/// Base type for all errors thrown by `init_tasks`.
abstract class InitException implements Exception {
  final String message;

  const InitException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// A task id was added twice to the same scheduler.
class DuplicateTaskException extends InitException {
  DuplicateTaskException(String taskId)
      : super(
          'Duplicate task id "$taskId". '
          'Task ids must be unique within a scheduler.',
        );
}

/// A task depends on a task that was never added to the scheduler.
class UnknownTaskException extends InitException {
  UnknownTaskException({required String taskId, required String dependencyId})
      : super(
          'Task "$taskId" depends on "$dependencyId", which was never added '
          'to the scheduler.',
        );
}

/// The dependency graph contains a cycle.
class DependencyCycleException extends InitException {
  /// The tasks forming the cycle, in order, with the first repeated at the end.
  final List<String> cycle;

  DependencyCycleException(this.cycle)
      : super('Dependency cycle detected: ${cycle.join(" -> ")}');
}

/// A task threw during [InitScheduler.run].
///
/// The original [error] and [stackTrace] are preserved.
class InitTaskFailedException extends InitException {
  final String taskId;
  final Object error;
  final StackTrace stackTrace;

  InitTaskFailedException(this.taskId, this.error, this.stackTrace)
      : super('Task "$taskId" failed: $error');
}

/// A task was skipped because one of its dependencies failed.
///
/// Only thrown/reported when running with `continueOnError: true`.
class DependencyFailedException extends InitException {
  DependencyFailedException(String taskId, String dependencyId)
      : super(
          'Task "$taskId" was skipped because dependency '
          '"$dependencyId" failed.',
        );
}
