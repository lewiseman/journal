import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ai_router.dart';
import '../core/ai_settings.dart';
import '../core/engine_registry.dart';
import '../core/on_device_engine.dart';
import '../models/model_catalog.dart';
import '../models/model_storage.dart';
import 'device_models_page.dart';

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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  task == AiTask.image
                      ? Icons.palette_outlined
                      : Icons.edit_note_rounded,
                  color: colors.primary,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _taskName(task),
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
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
                  : 'Summaries, rewrites and thoughtful answers.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant, height: 1.4),
            ),
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
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
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
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: ValueKey('device-get-model-${task.name}'),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.offline_bolt_outlined,
                size: 28,
                color: colors.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your offline setup',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Download a model. Take AI with you.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        for (final task in engine.supportedTasks) DeviceTaskCard(task: task),
        ListTile(
          key: const ValueKey('device-manage-models'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(Icons.folder_outlined, color: colors.primary),
          title: const Text('Manage models'),
          subtitle: ref
              .watch(deviceResourcesProvider)
              .when(
                data: (v) =>
                    Text('${modelBytes(v.freeBytes)} available on this phone'),
                loading: () => const Text('Checking storage…'),
                error: (_, _) => const Text('Downloads & storage'),
              ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _openModels(context),
        ),
      ],
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
