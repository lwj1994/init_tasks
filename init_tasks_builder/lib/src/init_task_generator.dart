import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:init_tasks/init_tasks.dart';
import 'package:source_gen/source_gen.dart';

/// Generates `buildInitScheduler()` for a library containing `@Init` classes.
///
/// The generated function instantiates every annotated class (in dependency
/// order) and wires them into a [InitScheduler] via their declared
/// `dependsOn` types.
class InitTaskGenerator extends Generator {
  static const _taskChecker = TypeChecker.fromRuntime(Init);

  @override
  FutureOr<String?> generate(LibraryReader library, BuildStep buildStep) async {
    final classes = [
      for (final cls in library.classes)
        if (_taskChecker.hasAnnotationOfExact(cls)) cls,
    ];
    if (classes.isEmpty) return null;

    final taskClasses = classes.toSet();
    final infos = [for (final cls in classes) _readTask(cls, taskClasses)];
    final ordered = _topoSort(infos);

    final varNames = <String, String>{};
    final usedNames = {for (final cls in classes) cls.name};
    String allocateName(String base) {
      var candidate = base;
      var suffix = 2;
      while (!usedNames.add(candidate)) {
        candidate = '$base${suffix++}';
      }
      return candidate;
    }

    final schedulerName = allocateName('scheduler');
    for (final info in ordered) {
      varNames[info.name] = allocateName('task${varNames.length}');
    }

    final buf = StringBuffer()
      ..writeln(
          '/// Builds a [InitScheduler] with every `@Init` in this library,')
      ..writeln('/// wired by their declared dependencies.')
      ..writeln('InitScheduler buildInitScheduler() {');
    for (final info in ordered) {
      buf.writeln('  final ${varNames[info.name]} = ${info.name}();');
    }
    buf.writeln('  final $schedulerName = InitScheduler();');
    for (final info in ordered) {
      final varName = varNames[info.name]!;
      if (info.dependsOn.isEmpty) {
        buf.writeln('  $schedulerName.add($varName);');
      } else {
        final deps = [for (final d in info.dependsOn) varNames[d]!];
        buf.writeln(
          '  $schedulerName.add($varName, dependsOn: [${deps.join(', ')}]);',
        );
      }
    }
    buf
      ..writeln('  return $schedulerName;')
      ..writeln('}');
    return buf.toString();
  }

  _TaskInfo _readTask(ClassElement cls, Set<ClassElement> taskClasses) {
    if (cls.isAbstract) {
      throw InvalidGenerationSourceError(
        '@Init class `${cls.name}` must not be abstract.',
        element: cls,
      );
    }
    final ctor = cls.unnamedConstructor;
    if (ctor == null ||
        ctor.isFactory ||
        ctor.parameters.any((p) => p.isRequired)) {
      throw InvalidGenerationSourceError(
        '@Init class `${cls.name}` must declare an unnamed constructor '
        'with no required parameters so the generator can instantiate it.',
        element: cls,
      );
    }

    final annotation = _taskChecker.firstAnnotationOfExact(cls)!;
    final reader = ConstantReader(annotation);
    final dependsOn = <String>[];
    for (final item in reader.read('dependsOn').listValue) {
      final type = item.toTypeValue();
      if (type is! InterfaceType || type.typeArguments.isNotEmpty) {
        throw InvalidGenerationSourceError(
          '@Init(dependsOn:) on `${cls.name}` must list task types, '
          'e.g. `dependsOn: [InitConfig]`.',
          element: cls,
        );
      }
      final depClass = type.element;
      final depName = depClass.name;
      if (!taskClasses.contains(depClass)) {
        throw InvalidGenerationSourceError(
          '@Init on `${cls.name}` depends on `$depName`, which is not a '
          '@Init class in this library. Keep all tasks of one scheduler in '
          'the same library and reference them by simple name.',
          element: cls,
        );
      }
      dependsOn.add(depName);
    }
    return _TaskInfo(cls.name, dependsOn);
  }

  /// Orders tasks so dependencies are instantiated first (readable output).
  List<_TaskInfo> _topoSort(List<_TaskInfo> infos) {
    final byName = {for (final i in infos) i.name: i};
    final visited = <String>{};
    final ordered = <_TaskInfo>[];
    void visit(String name) {
      if (!visited.add(name)) return;
      for (final dep in byName[name]!.dependsOn) {
        visit(dep);
      }
      ordered.add(byName[name]!);
    }

    for (final info in infos) {
      visit(info.name);
    }
    return ordered;
  }
}

class _TaskInfo {
  final String name;
  final List<String> dependsOn;

  _TaskInfo(this.name, this.dependsOn);
}
