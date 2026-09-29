# init_tasks_builder

Code generator for [`init_tasks`](https://pub.dev/packages/init_tasks).

Scans a library for `@Init`-annotated classes and generates a
`buildInitScheduler()` function that instantiates every task and wires
their `dependsOn` declarations into an `InitScheduler`.

## Setup

Add to your package's `dev_dependencies`:

```yaml
dev_dependencies:
  build_runner: ^2.4.0
  init_tasks_builder: ^0.1.0
```

The builder applies automatically (`auto_apply: dependents`). Then:

```sh
dart run build_runner build
```

## Input

```dart
import 'package:init_tasks/init_tasks.dart';

part 'app_init.g.dart';

@Init()
class InitConfig extends InitTask {
  @override
  Future<void> run() async {}
}

@Init(dependsOn: [InitConfig])
class InitDatabase extends InitTask {
  @override
  Future<void> run() async {}
}
```

## Output (`app_init.g.dart`)

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_init.dart';

InitScheduler buildInitScheduler() {
  final task0 = InitConfig();
  final task1 = InitDatabase();
  final scheduler = InitScheduler();
  scheduler.add(task0);
  scheduler.add(task1, dependsOn: [task0]);
  return scheduler;
}
```

## Constraints (enforced with clear build errors)

- One scheduler per library.
- `dependsOn` entries must be `@Init` classes in the same library,
  referenced by simple (unprefixed) name.
- Annotated classes must not be abstract and must declare an unnamed
  constructor with no required parameters.
