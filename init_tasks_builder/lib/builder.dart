import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/init_task_generator.dart';

/// Emits a `.init_task.g.part` per library, combined into `.g.dart` by
/// `source_gen:combining_builder`.
Builder initTaskBuilder(BuilderOptions options) =>
    SharedPartBuilder([InitTaskGenerator()], 'init_task');
