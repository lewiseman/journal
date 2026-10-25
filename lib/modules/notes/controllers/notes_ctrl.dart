import 'package:journal/common.dart';
import 'package:journal/modules/notes/controllers/notes_repository.dart';
import 'package:journal/modules/notes/models/note_tag.dart';

final StreamProvider<List<NoteEntity>> notesStreamProvider =
    StreamProvider<List<NoteEntity>>((ref) {
      final repo = ref.watch(notesRepositoryProvider);
      return repo.watchActiveNotes();
    });

final StreamProvider<List<NoteEntity>> trashNotesStreamProvider =
    StreamProvider<List<NoteEntity>>((ref) {
      final repo = ref.watch(notesRepositoryProvider);
      return repo.watchTrashNotes();
    });

final StreamProvider<List<NoteEntity>> conflictNotesStreamProvider =
    StreamProvider<List<NoteEntity>>((ref) {
      final repo = ref.watch(notesRepositoryProvider);
      return repo.watchConflictNotes();
    });

final notesRepositoryProvider = Provider<NotesRepository>((ref) {
  return NotesRepository(onDataChanged: () {});
});

final notesTagProvider = Provider<List<({String name, String emoji})>>((ref) {
  final notes = ref.watch(notesStreamProvider).asData?.value ?? const [];
  final uniqueTags = <String, NoteTag>{};

  for (final note in notes) {
    for (final tag in note.tags) {
      final parsed = NoteTag.tryParse(tag);
      if (parsed != null) uniqueTags.putIfAbsent(parsed.key, () => parsed);
    }
  }

  final tags =
      uniqueTags.values
          .map((tag) => (name: tag.name, emoji: tag.emoji))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  if (tags.isEmpty) {
    tags.addAll([(name: 'Ideas', emoji: '🪣'), (name: 'Work', emoji: '🍫')]);
  }
  tags.insert(tags.length ~/ 2, (name: 'All', emoji: '🐹'));
  return tags;
});
