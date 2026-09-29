import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:build/build.dart';
import 'package:init_tasks_builder/src/init_task_generator.dart';
import 'package:source_gen/source_gen.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory =
        await Directory.systemTemp.createTemp('init_tasks_builder_test_');
    final configUri = (await Isolate.packageConfig)!;
    final config = jsonDecode(await File.fromUri(configUri).readAsString())
        as Map<String, dynamic>;
    for (final entry in config['packages'] as List<dynamic>) {
      final package = entry as Map<String, dynamic>;
      package['rootUri'] =
          configUri.resolve(package['rootUri'] as String).toString();
    }
    await Directory('${directory.path}/.dart_tool').create();
    await File('${directory.path}/.dart_tool/package_config.json')
        .writeAsString(jsonEncode(config));
    await File('${directory.path}/pubspec.yaml').writeAsString(
      'name: generator_fixture\nenvironment:\n  sdk: ^3.0.0\n',
    );
  });

  tearDown(() => directory.delete(recursive: true));

  Future<String> generate(String source, {String? part}) async {
    final input = File('${directory.path}/tasks.dart');
    await input.writeAsString(source);
    await File('${directory.path}/tasks.g.dart')
        .writeAsString("part of 'tasks.dart';\n");
    if (part != null) {
      await File('${directory.path}/extra.dart').writeAsString(part);
    }
    final collection =
        AnalysisContextCollection(includedPaths: [directory.path]);
    try {
      final result = await collection
          .contextFor(input.path)
          .currentSession
          .getResolvedUnit(input.path) as ResolvedUnitResult;
      final output = await InitTaskGenerator().generate(
        LibraryReader(result.libraryElement),
        _UnusedBuildStep(),
      );
      await File('${directory.path}/tasks.g.dart')
          .writeAsString("part of 'tasks.dart';\n$output");
      return output!;
    } finally {
      await collection.dispose();
    }
  }

  Future<String> runGenerated() async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['tasks.dart'],
      workingDirectory: directory.path,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return (result.stdout as String).trim();
  }

  test('generated locals compile for keywords, private names and collisions',
      () async {
    final names = [
      'Scheduler',
      'Class',
      '_Private',
      'task0',
      'task02',
      'scheduler'
    ];
    await generate('''
import 'package:init_tasks/init_tasks.dart';
part 'tasks.g.dart';
${names.map((name) => '@Init() class $name extends InitTask { @override void run() {} }').join('\n')}
void main() {
  print(buildInitScheduler().tasks.map((task) => task.id).join(','));
}
''');
    expect(await runGenerated(), names.join(','));
  });

  test('rejects a foreign dependency with the same name as a local task',
      () async {
    await File('${directory.path}/foreign.dart').writeAsString('''
import 'package:init_tasks/init_tasks.dart';
@Init() class Config extends InitTask { @override void run() {} }
''');
    await expectLater(
      generate('''
import 'package:init_tasks/init_tasks.dart';
import 'foreign.dart' as foreign;
part 'tasks.g.dart';
@Init() class Config extends InitTask { @override void run() {} }
@Init(dependsOn: [foreign.Config])
class Boot extends InitTask { @override void run() {} }
'''),
      throwsA(isA<InvalidGenerationSourceError>().having(
        (e) => e.message,
        'message',
        contains('not a @Init class in this library'),
      )),
    );
  });

  test('wires a local dependency referenced through a type alias', () async {
    await generate('''
import 'package:init_tasks/init_tasks.dart';
part 'tasks.g.dart';
typedef ConfigAlias = Config;
@Init(dependsOn: [ConfigAlias])
class Boot extends InitTask { @override void run() {} }
@Init() class Config extends InitTask { @override void run() {} }
void main() {
  print(buildInitScheduler().resolve().map((level) => level.single.id).join(','));
}
''');
    expect(await runGenerated(), 'Config,Boot');
  });

  test('wires dependencies declared in another part of the same library',
      () async {
    await generate('''
import 'package:init_tasks/init_tasks.dart';
part 'tasks.g.dart';
part 'extra.dart';
@Init(dependsOn: [Config])
class Boot extends InitTask { @override void run() {} }
void main() {
  print(buildInitScheduler().resolve().map((level) => level.single.id).join(','));
}
''', part: '''
part of 'tasks.dart';
@Init() class Config extends InitTask { @override void run() {} }
''');
    expect(await runGenerated(), 'Config,Boot');
  });
}

class _UnusedBuildStep implements BuildStep {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('The generator must not access BuildStep here.');
}
