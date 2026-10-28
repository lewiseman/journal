import 'dart:convert';
import 'dart:typed_data';

import 'package:journal/modules/diary/history/diary_retrieval.dart';
import 'package:journal/modules/diary/models/diary_day_entity.dart';
import 'package:journal/modules/flow/models/thought_entity.dart';
import 'package:journal/modules/notes/models/note_entity.dart';

/// S03b embed operation, mirroring desktop/src/embed.cjs.
const embedOperation = 'embed';
const embedBatchItems = 8;
const embedTextBytes = 4000;
const embedInputBytes = 24000;

/// The phone's vector index is built for this size (see RecallVectorEntity).
const recallDimensions = 1024;

/// Cosine distance above which a vector match is not treated as related.
/// Measured with Qwen3 Embedding 0.6B Q8_0 on short journal entries
/// (2026-10-28): related English pairs 0.28–0.55, a Swahili entry for a
/// Swahili query 0.56, the closest unrelated entry 0.587.
const recallMaxDistance = 0.58;

enum RecallKind { diary, note, thought }

/// One piece of user text that can be embedded and found again.
class RecallSource {
  RecallSource({
    required this.kind,
    required this.id,
    required this.date,
    required String text,
    this.context = '',
  }) : text = boundedEmbedText(text),
       full = text;
  final RecallKind kind;
  final String id;

  /// Civil date `YYYY-MM-DD`.
  final String date;

  /// What is embedded: at most [embedTextBytes] of [full]. Long notes are
  /// matched by meaning on their beginning; keywords still cover all of it.
  final String text;
  final String full;

  /// Extra words matched by keyword only, such as the diary day's title.
  final String context;

  String get key => '${kind.name}:$id';
  String get hash => recallHash(text);

  static Iterable<RecallSource> diary(Iterable<DiaryDayEntity> days) sync* {
    for (final day in days) {
      if (day.isDeleted) continue;
      for (final item in day.visibleItems) {
        if (!sendableText(item.content)) continue;
        yield RecallSource(
          kind: RecallKind.diary,
          id: item.itemUuid,
          date: day.dateString,
          text: item.content.trim(),
          context: day.dayTitle ?? '',
        );
      }
    }
  }

  static Iterable<RecallSource> notes(Iterable<NoteEntity> notes) sync* {
    for (final note in notes) {
      if (note.isDeleted || note.deletedAt != null) continue;
      final text = '${note.title.trim()}\n${note.content.trim()}'.trim();
      if (!sendableText(text)) continue;
      yield RecallSource(
        kind: RecallKind.note,
        id: note.uuid,
        date: civilKey(note.createdAt.toLocal()),
        text: text,
      );
    }
  }

  static Iterable<RecallSource> thoughts(
    Iterable<ThoughtEntity> thoughts,
  ) sync* {
    for (final thought in thoughts) {
      final text = thought.content.trim();
      if (!sendableText(text)) continue;
      yield RecallSource(
        kind: RecallKind.thought,
        id: thought.uuid,
        date: civilKey(thought.createdAt.toLocal()),
        text: text,
      );
    }
  }
}

/// [text] cut to [embedTextBytes] UTF-8 bytes on a character boundary.
String boundedEmbedText(String text) {
  final value = text.trim();
  if (utf8.encode(value).length <= embedTextBytes) return value;
  final out = StringBuffer();
  var bytes = 0;
  for (final rune in value.runes) {
    final size = utf8.encode(String.fromCharCode(rune)).length;
    if (bytes + size > embedTextBytes) break;
    bytes += size;
    out.writeCharCode(rune);
  }
  return out.toString();
}

/// 64-bit FNV-1a of [text], hex.
String recallHash(String text) {
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(text)) {
    hash = (hash ^ byte) * 0x100000001b3;
  }
  return hash.toUnsigned(64).toRadixString(16);
}

/// Little-endian float32 vector from the companion's base64.
List<double> decodeVector(String base64Value, int dimensions) {
  final bytes = base64Decode(base64Value);
  if (bytes.length != dimensions * 4) {
    throw const FormatException('Vector has the wrong size');
  }
  final data = ByteData.sublistView(bytes);
  return List<double>.generate(dimensions, (i) {
    final v = data.getFloat32(i * 4, Endian.little);
    if (!v.isFinite) throw const FormatException('Vector is not finite');
    return v;
  }, growable: false);
}

/// One text to embed. [kind] is `query` or `document`.
class EmbedItem {
  const EmbedItem(this.id, this.kind, this.text);
  final String id, kind, text;
  Map<String, String> toJson() => {'id': id, 'kind': kind, 'text': text};
}
