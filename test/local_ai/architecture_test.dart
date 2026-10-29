import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only the engine registry can import an isolated engine', () {
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final path = file.path.replaceAll('\\', '/');
      if (path.contains('/local_ai/engines/qvac/') ||
          path.endsWith('/local_ai/core/engine_registry.dart')) {
        continue;
      }
      for (final match in RegExp(
        r'''(?:import|export)\s+['"]([^'"]+)['"]''',
      ).allMatches(file.readAsStringSync())) {
        expect(
          match[1]!.contains('engines/qvac') ||
              match[1]!.contains('qvac_bare_engine') ||
              match[1]!.contains('bare_rpc'),
          isFalse,
          reason: path,
        );
      }
    }
  });
  test('primitive server has no app operation or feature names', () {
    final file = File('native/qvac/entry.mjs');
    if (!file.existsSync()) return; // An empty engine registry is supported.
    final text = file.readAsStringSync();
    for (final name in [
      'summarize-note',
      'rewrite-note',
      'generate-note-background',
      'diary',
      'OperationRunner',
    ]) {
      expect(text.contains(name), isFalse, reason: name);
    }
  });
}
