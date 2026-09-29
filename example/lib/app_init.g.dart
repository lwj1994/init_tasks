// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_init.dart';

// **************************************************************************
// InitTaskGenerator
// **************************************************************************

/// Builds a [InitScheduler] with every `@Init` in this library,
/// wired by their declared dependencies.
InitScheduler buildInitScheduler() {
  final initConfig = InitConfig();
  final initDatabase = InitDatabase();
  final initCache = InitCache();
  final initUserSession = InitUserSession();
  final precacheImages = PrecacheImages();
  final scheduler = InitScheduler();
  scheduler.add(initConfig);
  scheduler.add(initDatabase, dependsOn: [initConfig]);
  scheduler.add(initCache, dependsOn: [initConfig]);
  scheduler.add(initUserSession, dependsOn: [initDatabase, initCache]);
  scheduler.add(precacheImages, dependsOn: [initUserSession]);
  return scheduler;
}
