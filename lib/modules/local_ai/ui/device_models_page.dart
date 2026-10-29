import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ai_router.dart';
import '../core/ai_settings.dart';
import '../core/engine_registry.dart';
import '../core/on_device_engine.dart';
import '../models/model_catalog.dart';
import '../models/model_downloader.dart';
import '../models/model_storage.dart';

final installedModelsProvider = FutureProvider<Set<String>>((ref) async {
  final models = await ref.watch(modelCatalogProvider.future),
      downloader = ref.watch(modelDownloaderProvider);
  return {
    for (final model in models)
      if (await downloader.installed(model)) model.id,
  };
});

final partialModelsProvider = FutureProvider<Map<String, int>>((ref) async {
  final models = await ref.watch(modelCatalogProvider.future);
  final downloader = ref.watch(modelDownloaderProvider);
  return {
    for (final model in models) model.id: await downloader.partialBytes(model),
  };
});

class ModelTransferState {
  const ModelTransferState({
    this.downloads = const {},
    this.progress = const {},
    this.errors = const {},
  });
  final Map<String, ModelDownload> downloads;
  final Map<String, DownloadProgress> progress;
  final Map<String, String> errors;
}

final modelTransfersProvider =
    NotifierProvider<ModelTransfers, ModelTransferState>(ModelTransfers.new);

class ModelTransfers extends Notifier<ModelTransferState> {
  @override
  ModelTransferState build() => const ModelTransferState();
  Future<void> discardPartial(CatalogModel model) async {
    await ref.read(modelDownloaderProvider).delete(model);
    if (!ref.mounted) return;
    state = ModelTransferState(
      downloads: state.downloads,
      progress: state.progress,
      errors: {...state.errors}..remove(model.id),
    );
    ref.invalidate(partialModelsProvider);
    ref.invalidate(deviceResourcesProvider);
  }

  Future<void> download(CatalogModel model) async {
    if (state.downloads.containsKey(model.id)) return;
    final transfer = ref
        .read(modelDownloaderProvider)
        .download(model, wifiOnly: ref.read(aiSettingsProvider).wifiOnly);
    state = ModelTransferState(
      downloads: {...state.downloads, model.id: transfer},
      progress: state.progress,
      errors: {...state.errors}..remove(model.id),
    );
    final subscription = transfer.progress.listen((p) {
      if (ref.mounted) {
        state = ModelTransferState(
          downloads: state.downloads,
          progress: {...state.progress, model.id: p},
          errors: state.errors,
        );
      }
    });
    try {
      await transfer.done;
    } catch (error) {
      if (ref.mounted) {
        state = ModelTransferState(
          downloads: state.downloads,
          progress: state.progress,
          errors: {
            ...state.errors,
            model.id: error is EngineFailure
                ? error.message
                : 'Download paused. Retry to resume.',
          },
        );
      }
    } finally {
      await subscription.cancel();
      if (ref.mounted) {
        state = ModelTransferState(
          downloads: {...state.downloads}..remove(model.id),
          progress: {...state.progress}..remove(model.id),
          errors: state.errors,
        );
        ref.invalidate(installedModelsProvider);
        ref.invalidate(partialModelsProvider);
        ref.invalidate(deviceResourcesProvider);
      }
    }
  }
}

class DeviceModelsPage extends ConsumerWidget {
  const DeviceModelsPage({super.key, this.task});
  final AiTask? task;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(onDeviceEngineProvider),
        settings = ref.watch(aiSettingsProvider);
    final installed = ref.watch(installedModelsProvider).asData?.value ?? {},
        transfers = ref.watch(modelTransfersProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (task) {
          AiTask.writing => 'Writing models',
          AiTask.image => 'Image models',
          AiTask.transcription => 'Voice models',
          null => 'Manage models',
        }),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SwitchListTile(
            title: const Text('Wi-Fi only'),
            subtitle: const Text('Downloads pause if Wi-Fi disconnects.'),
            value: settings.wifiOnly,
            onChanged: (v) =>
                ref.read(aiSettingsProvider.notifier).setWifiOnly(v),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Weights stay on this phone, outside backups. Only public, pinned files are downloaded. Allow extra storage and memory while models run.',
            ),
          ),
          ...ref
              .watch(modelCatalogProvider)
              .when(
                data: (models) => [
                  for (final model in models.where(
                    (m) =>
                        engine != null &&
                        (task == null || m.task == task) &&
                        engine.supportedTasks.contains(m.task) &&
                        engine.supportedModelFormats.contains(m.format),
                  ))
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              model.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              '${modelBytes(model.bytes)} · ${(model.minRamBytes / (1024 * 1024 * 1024)).round()} GB RAM · ${model.task.name}',
                            ),
                            Text(model.license),
                            if (transfers.errors[model.id] case final error?)
                              Text(
                                error,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            if (transfers.downloads[model.id]
                                case final transfer?) ...[
                              const SizedBox(height: 10),
                              LinearProgressIndicator(
                                value: transfers.progress[model.id]?.fraction,
                              ),
                              Text(
                                transfers.progress[model.id]?.verifying == true
                                    ? 'Verifying SHA-256…'
                                    : '${modelBytes(transfers.progress[model.id]?.received ?? 0)} / ${modelBytes(model.bytes)}',
                              ),
                              TextButton(
                                onPressed: transfer.cancel,
                                child: const Text('Cancel'),
                              ),
                            ] else if (installed.contains(model.id))
                              Row(
                                children: [
                                  const Icon(
                                    Icons.check_circle_outline,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text('Downloaded'),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: () async {
                                      try {
                                        if (ref
                                                .read(deviceJobBackendProvider)
                                                ?.busy ==
                                            true) {
                                          throw const EngineFailure(
                                            'BUSY',
                                            'Wait for the current task before deleting a model.',
                                          );
                                        }
                                        for (final task in AiTask.values) {
                                          if (settings.assignments[task] ==
                                              model.id) {
                                            await ref
                                                .read(
                                                  aiSettingsProvider.notifier,
                                                )
                                                .assign(task, null);
                                          }
                                        }
                                        await ref
                                            .read(modelDownloaderProvider)
                                            .delete(model);
                                        ref.invalidate(installedModelsProvider);
                                        ref.invalidate(deviceResourcesProvider);
                                      } catch (error) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    error is EngineFailure
                                                        ? error.message
                                                        : 'Could not remove this model.',
                                                  ),
                                                ),
                                              );
                                        }
                                      }
                                    },
                                    child: const Text('Delete'),
                                  ),
                                ],
                              )
                            else
                              TextButton.icon(
                                onPressed: () => unawaited(
                                  ref
                                      .read(modelTransfersProvider.notifier)
                                      .download(model),
                                ),
                                icon: const Icon(Icons.download_rounded),
                                label: Text(
                                  (ref
                                                  .watch(partialModelsProvider)
                                                  .asData
                                                  ?.value[model.id] ??
                                              0) >
                                          0
                                      ? 'Resume download'
                                      : 'Download',
                                ),
                              ),
                            if (!transfers.downloads.containsKey(model.id) &&
                                !installed.contains(model.id) &&
                                (ref
                                            .watch(partialModelsProvider)
                                            .asData
                                            ?.value[model.id] ??
                                        0) >
                                    0)
                              TextButton(
                                onPressed: () async {
                                  try {
                                    await ref
                                        .read(modelTransfersProvider.notifier)
                                        .discardPartial(model);
                                  } catch (_) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Could not discard this partial download.',
                                              ),
                                            ),
                                          );
                                    }
                                  }
                                },
                                child: Text(
                                  'Discard ${modelBytes(ref.watch(partialModelsProvider).asData!.value[model.id]!)} partial download',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
                loading: () => [
                  const Center(child: CircularProgressIndicator()),
                ],
                error: (_, _) => [
                  const Text('The model catalog could not be read.'),
                ],
              ),
        ],
      ),
    );
  }
}
