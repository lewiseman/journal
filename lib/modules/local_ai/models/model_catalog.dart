import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/on_device_engine.dart';

class CatalogModel {
  const CatalogModel({
    required this.id,
    required this.name,
    required this.task,
    required this.format,
    required this.repository,
    required this.revision,
    required this.file,
    required this.bytes,
    required this.sha256,
    required this.minRamBytes,
    required this.license,
    this.reasoningBudget,
  });
  final String id, name, format, repository, revision, file, sha256, license;
  final AiTask task;
  final int? reasoningBudget;
  final int bytes, minRamBytes;
  Uri get url =>
      Uri.https('huggingface.co', '/$repository/resolve/$revision/$file');
  factory CatalogModel.fromJson(Map<String, dynamic> j) {
    if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(j['revision'] as String) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(j['sha256'] as String) ||
        (j['bytes'] as int) <= 0 ||
        (j['file'] as String).contains('..')) {
      throw const FormatException('Unpinned model catalog entry');
    }
    return CatalogModel(
      id: j['id'],
      name: j['name'],
      task: AiTask.values.byName(j['task']),
      format: j['format'],
      repository: j['repository'],
      revision: j['revision'],
      file: j['file'],
      bytes: j['bytes'],
      sha256: j['sha256'],
      minRamBytes: j['minRamBytes'],
      license: j['license'],
      reasoningBudget: j['reasoningBudget'] as int?,
    );
  }
}

final modelCatalogProvider = FutureProvider<List<CatalogModel>>((ref) async {
  final j =
      jsonDecode(await rootBundle.loadString('assets/ai/models.json')) as Map;
  return (j['models'] as List)
      .map((m) => CatalogModel.fromJson(Map<String, dynamic>.from(m)))
      .toList();
});
String modelBytes(int bytes) => bytes >= 1000000000
    ? '${(bytes / 1000000000).toStringAsFixed(2)} GB'
    : '${(bytes / 1000000).ceil()} MB';
