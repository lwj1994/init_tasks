import 'package:init_tasks/init_tasks.dart';

part 'app_init.g.dart';

/// Example: app startup tasks wired purely by annotations.
/// Run `dart run build_runner build` to (re)generate `app_init.g.dart`.

@Init()
class InitConfig extends InitTask {
  @override
  Future<void> run() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    print('  config loaded');
  }
}

@Init(dependsOn: [InitConfig])
class InitDatabase extends InitTask {
  @override
  Future<void> run() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    print('  database opened');
  }
}

@Init(dependsOn: [InitConfig])
class InitCache extends InitTask {
  @override
  Future<void> run() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    print('  cache warmed');
  }
}

@Init(dependsOn: [InitDatabase, InitCache])
class InitUserSession extends InitTask {
  @override
  Future<void> run() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    print('  user session restored');
  }
}

@Init(dependsOn: [InitUserSession])
class PrecacheImages extends InitTask {
  @override
  Future<void> run() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    print('  images precached');
  }
}
