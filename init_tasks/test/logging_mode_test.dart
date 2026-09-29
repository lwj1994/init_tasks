import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

void main() {
  for (final release in [false, true]) {
    test('built-in logging respects product mode ($release)', () async {
      final config = File.fromUri((await Isolate.packageConfig)!).path;
      final result = await Process.run(Platform.resolvedExecutable, [
        '-Ddart.vm.product=$release',
        '--packages=$config',
        'test/fixtures/logging_probe.dart',
      ]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stderr, isEmpty);
      final output = result.stdout as String;
      if (release) {
        expect(output.trim(), 'complete');
      } else {
        for (final event in ['start', 'done', 'error', 'retry', 'skip']) {
          expect(output, contains('[init] $event'));
        }
        expect(output.trim(), endsWith('complete'));
      }
    });
  }
}
