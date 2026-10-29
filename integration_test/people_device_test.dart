import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:journal/modules/local_ai/core/on_device_engine.dart';
import 'package:journal/modules/local_ai/engines/qvac/qvac_bare_engine.dart';
import 'package:journal/modules/people/people_models.dart';
import 'package:journal/modules/people/people_transport.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('People and QVAC boot and stop independently on shared BareKit', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Checking independent worklets')),
        ),
      ),
    );
    final people = BarePeopleTransport(), qvac = QvacBareEngine();
    try {
      await tester.runAsync(() async {
        await qvac.start();
        final key = await people.start(peopleSecret(), 'Worklet test');
        expect(peopleKeyPattern.hasMatch(key), true);
        await people.configure([], null);
        await qvac.stop();
        await people.configure([], null); // QVAC shutdown did not stop People.
        await qvac.start();
        await people.stop();
        await qvac.unload(AiTask.writing); // People shutdown did not stop QVAC.
      });
    } finally {
      await tester.runAsync(() async {
        await people.dispose();
        await qvac.stop();
      });
    }
  }, skip: !Platform.isAndroid);
}
