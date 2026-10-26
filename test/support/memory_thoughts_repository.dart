import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/flow/controllers/thoughts_repository.dart';
import 'package:journal/modules/flow/models/thought_entity.dart';

/// Deterministic saved records for Flow layout tests; never shown in production.
List<ThoughtEntity> sampleThoughts([int count = 12]) {
  const content = [
    'Maybe a slower morning is a good place to start.',
    'I want to make more things just for the joy of making them.',
    'That little walk cleared more space in my head than I expected.',
    'A reminder to myself: I don’t have to figure it all out today.',
    'What if I said yes to the idea I keep coming back to?',
    'Coffee, an open window, and nowhere to rush. More of this, please.',
    'I felt most like myself when I stopped trying to be productive for a moment.',
    'An idea for the weekend: take the long way home and see what I notice.',
    'Some things feel smaller once I put them into words.',
    'I should tell the people I love about the little things they do that stay with me.',
    'Learning to leave a little room for things I didn’t plan.',
    'There was a moment today when everything felt quietly okay. I want to remember that.',
  ];
  final now = DateTime.now();
  return [
    for (var i = 0; i < count; i++)
      ThoughtEntity(
        id: i + 1,
        uuid: '$i',
        content: content[i % content.length],
        createdAt: now.subtract(Duration(hours: i + 1)),
      ),
  ];
}

class MemoryThoughtsRepository extends Fake implements ThoughtsRepository {
  MemoryThoughtsRepository(this.thoughts);

  final List<ThoughtEntity> thoughts;
  final changes = StreamController<List<ThoughtEntity>>.broadcast();
  bool failSaves = false;
  bool failReads = false;
  bool holdReads = false;

  @override
  ThoughtEntity saveThought({required String content}) {
    if (failSaves) throw StateError('Disk unavailable');
    final thought = ThoughtEntity(
      id: thoughts.length + 1,
      uuid: '${thoughts.length}',
      content: content.trim(),
      createdAt: DateTime.now(),
    );
    thoughts.insert(0, thought);
    changes.add(List.of(thoughts));
    return thought;
  }

  @override
  Stream<List<ThoughtEntity>> watchThoughts() => Stream.multi((events) {
    final subscription = changes.stream.listen(
      events.add,
      onError: events.addError,
    );
    if (failReads) {
      events.addError(StateError('Read unavailable'));
    } else if (!holdReads) {
      events.add(List.of(thoughts));
    }
    events.onCancel = subscription.cancel;
  });
}
