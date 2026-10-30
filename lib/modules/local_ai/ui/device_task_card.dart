import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ai_router.dart';
import '../core/ai_settings.dart';
import '../core/engine_registry.dart';
import '../core/on_device_engine.dart';
import '../models/model_catalog.dart';
import '../models/model_storage.dart';
import 'device_models_page.dart';
import 'ai_studio_material.dart';

String _taskName(AiTask task) => switch (task) {
  AiTask.writing => 'Writing & answers',
  AiTask.image => 'Image generation',
  AiTask.transcription => 'Voice to text',
};

void _openModels(BuildContext context, {AiTask? task}) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => DeviceModelsPage(task: task)));

class DeviceTaskCard extends ConsumerWidget {
  const DeviceTaskCard({super.key, required this.task});
  final AiTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(onDeviceEngineProvider);
    if (engine == null || !engine.supportedTasks.contains(task)) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    final settings = ref.watch(aiSettingsProvider);
    final installedState = ref.watch(installedModelsProvider);
    final catalogState = ref.watch(modelCatalogProvider);
    final installed = installedState.asData?.value ?? {};
    final models = (catalogState.asData?.value ?? [])
        .where(
          (m) =>
              m.task == task &&
              engine.supportedModelFormats.contains(m.format) &&
              installed.contains(m.id),
        )
        .toList();
    final assignment = models
        .where((m) => m.id == settings.assignments[task])
        .firstOrNull;
    final checking = installedState.isLoading || catalogState.isLoading;
    final failed = installedState.hasError || catalogState.hasError;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                switch (task) {
                  AiTask.transcription => Icons.mic_none_rounded,
                  AiTask.image => Icons.image_outlined,
                  AiTask.writing => Icons.edit_note_rounded,
                },
                color: colors.primary,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _taskName(task),
                  style: studioTitle(context, size: 18),
                ),
              ),
              if (assignment != null)
                Tooltip(
                  message: 'Model ready on this phone',
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: colors.primary,
                    size: 20,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            checking
                ? 'Checking your models…'
                : failed
                ? 'Could not check your downloaded models.'
                : task == AiTask.image
                ? 'Create a background for your notes.'
                : task == AiTask.transcription
                ? 'Turn spoken moments into written words.'
                : 'Summaries, rewrites and thoughtful answers.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.onSurfaceVariant, height: 1.4),
          ),
          if (!checking && !failed && models.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              assignment == null
                  ? 'Choose a downloaded model to finish setup.'
                  : 'Ready on this phone',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: assignment == null
                    ? colors.onSurfaceVariant
                    : colors.primary,
              ),
            ),
          ],
          if (failed)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  ref.invalidate(modelCatalogProvider);
                  ref.invalidate(installedModelsProvider);
                },
                child: const Text('Try again'),
              ),
            )
          else if (models.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('device-model-${task.name}-${assignment?.id}'),
              isExpanded: true,
              initialValue: assignment?.id,
              decoration: InputDecoration(
                labelText: 'Model on this phone',
                border: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: colors.primary.withValues(alpha: .25),
                  ),
                ),
              ),
              hint: const Text('Choose a model'),
              items: [
                for (final model in models)
                  DropdownMenuItem(
                    value: model.id,
                    child: Text(model.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) async {
                try {
                  if (ref.read(deviceJobBackendProvider)?.busy == true) {
                    throw const EngineFailure(
                      'BUSY',
                      'Wait for the current task before changing its model.',
                    );
                  }
                  await ref
                      .read(aiSettingsProvider.notifier)
                      .assign(task, value);
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          error is EngineFailure
                              ? error.message
                              : 'Could not save your model choice.',
                        ),
                      ),
                    );
                  }
                }
              },
            ),
          ] else if (!checking)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: OutlinedButton.icon(
                key: ValueKey('device-get-model-${task.name}'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  side: BorderSide(
                    color: colors.primary.withValues(alpha: .25),
                  ),
                ),
                onPressed: () => _openModels(context, task: task),
                icon: const Icon(Icons.download_rounded, size: 19),
                label: Text(
                  task == AiTask.image
                      ? 'Get an image model'
                      : 'Get a writing model',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DeviceAiSection extends ConsumerWidget {
  const DeviceAiSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(onDeviceEngineProvider);
    if (engine == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final installed = ref.watch(installedModelsProvider);
    final catalog = ref.watch(modelCatalogProvider);
    final settings = ref.watch(aiSettingsProvider);
    final tasks = engine.supportedTasks;
    final ready = tasks.where((task) {
      final id = settings.assignments[task];
      return id != null &&
          (installed.asData?.value.contains(id) ?? false) &&
          (catalog.asData?.value.any(
                (model) =>
                    model.id == id &&
                    model.task == task &&
                    engine.supportedModelFormats.contains(model.format),
              ) ??
              false);
    }).length;
    final checking = installed.isLoading || catalog.isLoading;
    final failed = installed.hasError || catalog.hasError;
    return AiStudioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.offline_bolt_outlined,
                color: colors.primary,
                size: 32,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your offline setup',
                      style: studioTitle(context, size: 23),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Download a model. Take AI with you.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(
              checking
                  ? 'Checking your offline setup…'
                  : failed
                  ? 'Your models could not be checked'
                  : '$ready of ${tasks.length} tools ready on this phone',
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: colors.primary),
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: checking
                  ? null
                  : (tasks.isEmpty ? 0 : ready / tasks.length),
              minHeight: 3,
              backgroundColor: colors.primaryContainer.withValues(alpha: .45),
            ),
          ),
          const SizedBox(height: 18),
          for (final task in tasks) ...[
            DeviceTaskCard(task: task),
            Divider(height: 1, color: colors.onSurface.withValues(alpha: .1)),
          ],
          ListTile(
            key: const ValueKey('device-manage-models'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: Icon(Icons.folder_outlined, color: colors.primary),
            title: const Text('Manage models'),
            subtitle: ref
                .watch(deviceResourcesProvider)
                .when(
                  data: (v) => Text(
                    '${modelBytes(v.freeBytes)} available on this phone',
                  ),
                  loading: () => const Text('Checking storage…'),
                  error: (_, _) => const Text('Downloads & storage'),
                ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openModels(context),
          ),
        ],
      ),
    );
  }
}

/// Optional exceptions stay out of the everyday model setup.
class AiTaskPreferences extends ConsumerWidget {
  const AiTaskPreferences({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(onDeviceEngineProvider);
    if (engine == null) return const SizedBox.shrink();
    final settings = ref.watch(aiSettingsProvider);
    final custom = engine.supportedTasks
        .where(
          (task) => (settings.overrides[task] ?? AiMode.auto) != AiMode.auto,
        )
        .length;
    return ExpansionTile(
      key: const ValueKey('ai-task-preferences'),
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      childrenPadding: const EdgeInsets.only(top: 8, bottom: 12),
      shape: const Border(),
      collapsedShape: const Border(),
      title: const Text('Advanced'),
      subtitle: Text(
        custom == 0
            ? 'Every task follows your choice above'
            : '$custom custom task ${custom == 1 ? 'choice' : 'choices'}',
      ),
      children: [
        for (final task in engine.supportedTasks)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: DropdownButtonFormField<AiMode>(
              key: ValueKey(
                'ai-task-route-${task.name}-${settings.overrides[task]}',
              ),
              isExpanded: true,
              initialValue: settings.overrides[task] ?? AiMode.auto,
              decoration: InputDecoration(
                labelText: _taskName(task),
                border: const OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: AiMode.auto,
                  child: Text('Follow choice above'),
                ),
                DropdownMenuItem(
                  value: AiMode.companion,
                  child: Text('Companion'),
                ),
                DropdownMenuItem(
                  value: AiMode.device,
                  child: Text('On this phone'),
                ),
              ],
              onChanged: (value) async {
                if (value == null) return;
                try {
                  await ref
                      .read(aiSettingsProvider.notifier)
                      .setOverride(task, value);
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not save this task preference.'),
                      ),
                    );
                  }
                }
              },
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Device engine: ${engine.displayName}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        ref
            .watch(deviceResourcesProvider)
            .maybeWhen(
              data: (v) => Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${(v.ramBytes / (1024 * 1024 * 1024)).round()} GB memory',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
      ],
    );
  }
}
