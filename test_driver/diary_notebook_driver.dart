import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data == null) return;
    final phase = data['phase'];
    await File('/tmp/journal-notebook-$phase.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  },
);
