import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';

import '../models/model_catalog.dart';
import '../models/model_downloader.dart';
import '../models/model_storage.dart';
import 'ai_settings.dart';
import 'device_job_backend.dart';
import 'engine_registry.dart';
import 'on_device_engine.dart';

/// A pinned execution destination; a local destination is never a trusted
/// computer or a set of network credentials.
class AiJobProvider {
  const AiJobProvider.companion(this.computer, this.operation)
    : kind = AiProviderKind.companion,
      accepted = false;
  const AiJobProvider.device(this.operation, {this.accepted = false})
    : computer = null,
      kind = AiProviderKind.device;
  final AiProviderKind kind;
  final TrustedComputer? computer;
  final String operation;
  final bool accepted;
  String get id => computer?.id ?? 'this-phone';
  String get deviceId => computer?.deviceId ?? 'this-phone';
}

/// Pure decision table. Auto selects once at submission; execution never fails
/// over to another machine. Explicit provider choices fail with a reason.
AiProviderKind chooseAiProvider({
  required AiMode mode,
  AiMode override = AiMode.auto,
  required bool companionConnected,
  required bool deviceReady,
}) {
  final choice = override == AiMode.auto ? mode : override;
  if (choice == AiMode.device) {
    if (!deviceReady) {
      throw const CompanionFailure(
        'NOT_READY',
        'On this phone is unavailable for this task. Download and assign a compatible model in Local AI.',
      );
    }
    return AiProviderKind.device;
  }
  if (choice == AiMode.companion || companionConnected) {
    if (!companionConnected) {
      throw const CompanionFailure(
        'UNAVAILABLE',
        'Connect your trusted computer in Local AI.',
      );
    }
    return AiProviderKind.companion;
  }
  if (deviceReady) return AiProviderKind.device;
  throw const CompanionFailure(
    'NOT_READY',
    'No provider is ready. Connect your companion or set up a model on this phone.',
  );
}

AiTask? operationTask(String operation) => switch (operation) {
  'generate-note-background' => AiTask.image,
  'summarize-note' ||
  'rewrite-note' ||
  'expand-note' ||
  'tone-note' ||
  'clarify-note' ||
  'markdown-note' ||
  'reflect-thought' ||
  'suggest-note-metadata' ||
  'suggest-note-ideas' ||
  'suggest-note-template' ||
  'suggest-diary-day' ||
  'ask-diary-question' ||
  'answer-diary-question' ||
  'answer-note-question' ||
  'answer-thought-question' => AiTask.writing,
  _ => null,
};

class AiRouter {
  const AiRouter({
    required this.settings,
    required this.engine,
    required this.companionConnected,
    required this.models,
  });
  final AiSettings settings;
  final OnDeviceEngine? engine;
  final bool companionConnected;
  final List<CatalogModel> models;
  CatalogModel? assigned(AiTask task) => models
      .where(
        (m) =>
            m.id == settings.assignments[task] &&
            m.task == task &&
            (engine?.supportedModelFormats.contains(m.format) ?? false),
      )
      .firstOrNull;
  AiProviderKind select(String operation) {
    final task = operationTask(operation);
    // Vision, OCR, websites, voice and unknown operations stay companion-only.
    final ready =
        task != null &&
        engine != null &&
        engine!.supportedTasks.contains(task) &&
        assigned(task) != null;
    return chooseAiProvider(
      mode: settings.mode,
      override: task == null
          ? AiMode.auto
          : settings.overrides[task] ?? AiMode.auto,
      companionConnected: companionConnected,
      deviceReady: ready,
    );
  }
}

final aiRouterProvider = Provider<AiRouter>(
  (ref) => AiRouter(
    settings: ref.watch(aiSettingsProvider),
    engine: ref.watch(onDeviceEngineProvider),
    companionConnected:
        ref.watch(companionControllerProvider).phase ==
        CompanionPhase.connected,
    models: ref.watch(modelCatalogProvider).asData?.value ?? const [],
  ),
);

final modelDownloaderProvider = Provider<ModelDownloader>((ref) {
  final value = ModelDownloader(storage: ref.watch(modelStorageProvider));
  ref.onDispose(value.cancelAll);
  return value;
});
final deviceJobBackendProvider = Provider<DeviceJobBackend?>((ref) {
  final engine = ref.watch(onDeviceEngineProvider);
  if (engine == null) return null;
  final value = DeviceJobBackend(
    engine: engine,
    storage: ref.watch(modelStorageProvider),
    downloader: ref.watch(modelDownloaderProvider),
  );
  ref.onDispose(value.dispose);
  return value;
});
final aiJobClientProvider = Provider<AiJobClient>(
  (ref) => AiJobClient(
    companion: CompanionClient(ref.watch(companionTransportProvider)),
    device: () => ref.read(deviceJobBackendProvider),
    router: () => ref.read(aiRouterProvider),
  ),
);

class AiJobClient {
  const AiJobClient({
    required this.companion,
    required this.device,
    required this.router,
  });
  final CompanionClient companion;
  final DeviceJobBackend? Function() device;
  final AiRouter Function() router;
  Future<Map<String, dynamic>> authenticated(
    AiJobProvider provider,
    String method,
    String route, {
    Map<String, dynamic>? body,
  }) async {
    if (provider.kind == AiProviderKind.companion) {
      final remote = body == null
          ? null
          : (Map<String, dynamic>.of(body)..remove('localSource'));
      return companion.authenticated(
        provider.computer!,
        method,
        route,
        body: remote,
      );
    }
    final backend = device();
    if (backend == null) {
      // An engine removed by an app update cannot retain running local work.
      // Resolve old handles terminally so they can be cleared; never reroute or
      // resubmit their protected input to the companion.
      if (route.startsWith('/v1/jobs/') &&
          (method == 'GET' ||
              route.endsWith('/cancel') ||
              route.endsWith('/ack'))) {
        return {
          'id': route.split('/')[3],
          'operation': provider.operation,
          'device': 'this-phone',
          'model': 'removed-engine',
          'state': route.endsWith('/cancel') ? 'cancelled' : 'interrupted',
          'acknowledged': route.endsWith('/ack'),
        };
      }
      throw const CompanionFailure(
        'NOT_READY',
        'No on-device engine is installed.',
      );
    }
    final input = body == null ? null : Map<String, dynamic>.of(body);
    if (route == '/v1/jobs' && method == 'POST') {
      final task = operationTask(provider.operation);
      final model = task == null ? null : router().assigned(task);
      if (model == null) {
        throw const CompanionFailure(
          'NOT_READY',
          'Assign a model for this task in Local AI.',
        );
      }
      input!['_model'] = model;
      input['modelId'] = model.id;
    }
    try {
      return await backend.request(method, route, body: input);
    } on CompanionFailure catch (error) {
      // An accepted in-memory job cannot survive process death. Keep its receipt
      // terminal; never run its protected prompt again automatically.
      if (error.code == 'NOT_FOUND' &&
          provider.accepted &&
          route.startsWith('/v1/jobs/')) {
        return {
          'id': route.split('/')[3],
          'operation': provider.operation,
          'device': 'this-phone',
          'model': 'interrupted',
          'state': route.endsWith('/cancel') ? 'cancelled' : 'interrupted',
          'acknowledged': route.endsWith('/ack'),
        };
      }
      rethrow;
    } on EngineFailure catch (error) {
      throw CompanionFailure(error.code, error.message);
    }
  }
}

AiJobProvider capableProvider(
  Ref ref, {
  required String contractKey,
  required int contract,
  required String operation,
  required String fallback,
  required String update,
  String capabilityId = 'text',
  String notReady = 'Load the writing model on your computer.',
  String notReadyCode = 'NOT_READY',
}) {
  if (ref.read(aiRouterProvider).select(operation) == AiProviderKind.device) {
    return AiJobProvider.device(operation);
  }
  final connection = ref.read(companionControllerProvider),
      computer = connection.selected;
  if (computer == null ||
      !computer.enabled ||
      connection.phase != CompanionPhase.connected) {
    throw CompanionFailure(
      'UNAVAILABLE',
      'Connect your trusted computer in Local AI. $fallback',
    );
  }
  final capability = (connection.status?['capabilities'] as List? ?? [])
      .whereType<Map>()
      .where((c) => c['id'] == capabilityId)
      .firstOrNull;
  if (connection.status?['recovery'] != 1 ||
      (contractKey.isNotEmpty && capability?[contractKey] != contract) ||
      capability?['operations'] is! List ||
      !(capability!['operations'] as List).contains(operation)) {
    throw CompanionFailure('INCOMPATIBLE_VERSION', update);
  }
  if (!['ready', 'busy'].contains(capability['status'])) {
    throw CompanionFailure(notReadyCode, '$notReady $fallback');
  }
  return AiJobProvider.companion(computer, operation);
}

/// Feature availability follows the same routing decision as submission.
final aiOperationAvailableProvider = Provider.family<bool, String>((
  ref,
  operation,
) {
  try {
    ref.watch(aiRouterProvider).select(operation);
    return true;
  } on CompanionFailure {
    return false;
  }
});
