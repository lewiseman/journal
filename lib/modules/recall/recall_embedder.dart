import 'dart:async';
import 'dart:convert';

import 'package:journal/modules/recall/recall_contract.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';
import 'package:uuid/uuid.dart';

/// What the paired computer reports about its embedding model.
class EmbeddingCapability {
  const EmbeddingCapability(this.model, this.dimensions);
  final String model;
  final int dimensions;

  /// The ready embedding capability in a `/v1/status` reply, or null.
  static EmbeddingCapability? fromStatus(Map<String, dynamic>? status) {
    for (final c in (status?['capabilities'] as List? ?? const [])) {
      if (c is Map &&
          c['id'] == 'embedding' &&
          c['status'] == 'ready' &&
          c['model'] is String &&
          c['dimensions'] == recallDimensions) {
        return EmbeddingCapability(c['model'] as String, recallDimensions);
      }
    }
    return null;
  }
}

/// Turns texts into vectors with the companion's embedding model.
abstract interface class TextEmbedder {
  /// Vectors by item id, all from [model]. Throws [CompanionFailure].
  Future<Map<String, List<double>>> embed(String model, List<EmbedItem> items);
}

/// Sends one durable `embed` job per batch and collects it promptly. The
/// job's text is dropped by the computer on completion and its vectors on
/// acknowledgement.
class CompanionTextEmbedder implements TextEmbedder {
  CompanionTextEmbedder({
    required this.computer,
    CompanionTransport Function()? transportFactory,
    this.poll = const Duration(milliseconds: 120),
    this.timeout = const Duration(seconds: 60),
  }) : transportFactory = transportFactory ?? PinnedCompanionTransport.new;
  final TrustedComputer Function() computer;
  final CompanionTransport Function() transportFactory;
  final Duration poll, timeout;

  @override
  Future<Map<String, List<double>>> embed(
    String model,
    List<EmbedItem> items,
  ) async {
    final prompt = jsonEncode({
      'model': model,
      'items': [for (final i in items) i.toJson()],
    });
    if (items.isEmpty ||
        items.length > embedBatchItems ||
        utf8.encode(prompt).length > embedInputBytes) {
      throw const CompanionFailure('INPUT_LIMIT', 'Embedding batch too large.');
    }
    final c = computer();
    final transport = transportFactory();
    final client = CompanionClient(transport);
    final id = const Uuid().v4();
    try {
      var job = await client.authenticated(
        c,
        'POST',
        '/v1/jobs',
        body: {
          'id': id,
          'operation': embedOperation,
          'prompt': prompt,
          'expires': DateTime.now()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        },
      );
      final deadline = DateTime.now().add(timeout);
      while (['queued', 'running'].contains(job['state'])) {
        if (DateTime.now().isAfter(deadline)) {
          try {
            await client.authenticated(
              c,
              'POST',
              '/v1/jobs/$id/cancel',
              body: {'operation': embedOperation},
            );
          } catch (_) {}
          throw const CompanionFailure(
            'TIMEOUT',
            'Your computer did not finish embedding in time.',
          );
        }
        await Future<void>.delayed(poll);
        job = await client.authenticated(c, 'GET', '/v1/jobs/$id');
      }
      if (job['id'] != id || job['operation'] != embedOperation) {
        throw const FormatException();
      }
      if (job['state'] != 'completed') {
        throw CompanionFailure(
          job['error'] as String? ?? 'FAILED',
          job['error'] == 'MODEL_CHANGED'
              ? 'Your computer switched embedding model.'
              : 'Your computer could not embed this text.',
        );
      }
      final out = jsonDecode(job['text'] as String) as Map<String, dynamic>;
      final dimensions = out['dimensions'];
      if (out['model'] != model || dimensions != recallDimensions) {
        throw const CompanionFailure(
          'MODEL_CHANGED',
          'Your computer switched embedding model.',
        );
      }
      final vectors = {
        for (final v in out['vectors'] as List)
          (v as Map)['id'] as String: decodeVector(
            v['vector'] as String,
            recallDimensions,
          ),
      };
      if (!items.every((i) => vectors.containsKey(i.id)) ||
          vectors.length != items.length) {
        throw const FormatException();
      }
      try {
        await client.authenticated(c, 'POST', '/v1/jobs/$id/ack');
      } catch (_) {
        // The computer still drops the vectors when the job expires.
      }
      return vectors;
    } on FormatException {
      throw const CompanionFailure(
        'INVALID_RESPONSE',
        'Your computer returned invalid vectors.',
      );
    } on TypeError {
      throw const CompanionFailure(
        'INVALID_RESPONSE',
        'Your computer returned invalid vectors.',
      );
    } finally {
      transport.close();
    }
  }
}
