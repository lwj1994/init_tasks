## 0.1.0

- Initial rewrite: `InitScheduler` with instance-based `add(task, dependsOn: [...])`.
- Topological levels executed with `Future.wait` (independent tasks run concurrently).
- `run()` returns `Future<void>`; `resolve()` validates without executing.
- Typed errors: `DependencyCycleException` (with cycle path), `UnknownTaskException`,
  `DuplicateTaskException`, `InitTaskFailedException`, `DependencyFailedException`.
- Per-task `timeout` / `retries`; `continueOnError` mode; `InitObserver` lifecycle hooks.
- `@Init(dependsOn: [Type])` annotation + `init_tasks_builder` codegen
  emitting `buildInitScheduler()`.
