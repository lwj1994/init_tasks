import 'dart:async';

import 'package:meta/meta_meta.dart';

/// Base class for tasks run by [InitScheduler].
///
/// Extend it and override [run]. [id] defaults to the runtime class name
/// and must be unique within a single scheduler.
abstract class InitTask {
  /// Unique id within a scheduler. Defaults to the runtime class name.
  ///
  /// Override it when two instances of the same class need to coexist,
  /// or when you want a stable hand-written id.
  String get id => runtimeType.toString();

  /// The work to perform. May complete synchronously or asynchronously.
  FutureOr<void> run();
}

/// Marks a class as an init task for `init_tasks_builder` codegen.
///
/// ```dart
/// @Init()
/// class InitConfig extends InitTask {
///   @override
///   Future<void> run() async { ... }
/// }
///
/// @Init(dependsOn: [InitConfig])
/// class InitDatabase extends InitTask {
///   @override
///   Future<void> run() async { ... }
/// }
/// ```
///
/// The generator emits a `buildInitScheduler()` function that wires every
/// annotated class in the library. Dependencies are [Type]s, so a rename
/// or a typo is a compile-time error — never a silent scheduling bug.
///
/// Annotated classes must expose an unnamed constructor without required
/// parameters so the generator can instantiate them.
@Target({TargetKind.classType})
class Init {
  /// Task types that must finish before the annotated task runs.
  final List<Type> dependsOn;

  const Init({this.dependsOn = const []});
}
