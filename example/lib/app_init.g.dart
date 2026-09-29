// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_init.dart';

// **************************************************************************
// InitTaskGenerator
// **************************************************************************

/// Builds a [InitScheduler] with every `@Init` in this library,
/// wired by their declared dependencies.
InitScheduler buildInitScheduler() {
  final task0 = InitConfig();
  final task1 = InitDatabase();
  final task2 = InitCache();
  final task3 = InitUserSession();
  final task4 = PrecacheImages();
  final scheduler = InitScheduler();
  scheduler.add(task0);
  scheduler.add(task1, dependsOn: [task0]);
  scheduler.add(task2, dependsOn: [task0]);
  scheduler.add(task3, dependsOn: [task1, task2]);
  scheduler.add(task4, dependsOn: [task3]);
  return scheduler;
}
