import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// I06: an optional generated note background.
const noteBackgroundOperation = 'generate-note-background';
const noteBackgroundContract = 1;
const noteBackgroundPromptChars = 240;
const noteBackgroundTones = {'light': 'Light', 'dark': 'Dark'};

/// Previews the user has not accepted are deleted after this long.
const noteBackgroundPreviewLifetime = Duration(hours: 24);

final _control = RegExp(r'[\x00-\x1f\x7f]');

/// Canonical JSON so equal backgrounds compare equal regardless of key order.
String canonicalBackground(Map<String, dynamic> background) => jsonEncode({
  for (final key in background.keys.toList()..sort()) key: background[key],
});

/// What was requested, and the note's background at that moment. Only
/// [prompt] and [tone] are sent.
class NoteBackgroundRequest {
  const NoteBackgroundRequest({
    required this.noteId,
    required this.prompt,
    required this.tone,
    required this.background,
  });
  final String noteId, prompt, tone;
  final Map<String, dynamic> background;

  /// Throws [FormatException] for an empty, long or multi-line description.
  String request() {
    final text = prompt.trim();
    if (text.isEmpty ||
        text.runes.length > noteBackgroundPromptChars ||
        _control.hasMatch(text) ||
        !noteBackgroundTones.containsKey(tone)) {
      throw const FormatException(
        'Describe the background in one line of at most 240 characters.',
      );
    }
    return jsonEncode({'prompt': text, 'tone': tone});
  }

  String encode() => jsonEncode({
    'noteId': noteId,
    'prompt': prompt,
    'tone': tone,
    'background': background,
  });
  factory NoteBackgroundRequest.decode(String raw) {
    final json = jsonDecode(raw);
    if (json is! Map ||
        json['noteId'] is! String ||
        json['prompt'] is! String ||
        !noteBackgroundTones.containsKey(json['tone']) ||
        json['background'] is! Map) {
      throw const FormatException('Invalid background request');
    }
    return NoteBackgroundRequest(
      noteId: json['noteId'] as String,
      prompt: json['prompt'] as String,
      tone: json['tone'] as String,
      background: (json['background'] as Map).cast<String, dynamic>(),
    );
  }
}

/// The computer's description of a finished image (not the image itself).
class NoteBackgroundResult {
  const NoteBackgroundResult({
    required this.width,
    required this.height,
    required this.bytes,
    required this.sha256,
    required this.seed,
  });
  final int width, height, bytes, seed;
  final String sha256;

  factory NoteBackgroundResult.parse(String raw) {
    final json = jsonDecode(raw);
    if (json is! Map ||
        json['width'] is! int ||
        json['height'] is! int ||
        json['bytes'] is! int ||
        json['seed'] is! int ||
        json['sha256'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(json['sha256'] as String) ||
        (json['width'] as int) < 64 ||
        (json['width'] as int) > 2048 ||
        (json['height'] as int) < 64 ||
        (json['height'] as int) > 2048 ||
        (json['bytes'] as int) <= 0 ||
        (json['bytes'] as int) > 4 * 1024 * 1024) {
      throw const FormatException('Invalid background result');
    }
    return NoteBackgroundResult(
      width: json['width'] as int,
      height: json['height'] as int,
      bytes: json['bytes'] as int,
      sha256: json['sha256'] as String,
      seed: json['seed'] as int,
    );
  }

  /// Whether [png] is the promised image.
  bool matches(Uint8List png, String digest) =>
      digest == sha256 &&
      png.length == bytes &&
      png.length > 24 &&
      png[0] == 0x89 &&
      png[1] == 0x50 &&
      ByteData.sublistView(png).getUint32(16) == width &&
      ByteData.sublistView(png).getUint32(20) == height;
}

/// A revertible accepted background: what it replaced.
class NoteBackgroundRecovery {
  const NoteBackgroundRecovery({
    required this.noteId,
    required this.previous,
    required this.accepted,
  });
  final String noteId;
  final Map<String, dynamic> previous, accepted;
}

final noteBackgroundStoreProvider = Provider<NoteBackgroundStore>(
  (ref) => NoteBackgroundStore(),
);

/// Generated images live in `<support>/note_backgrounds/generated`, inside
/// the folder account reset already removes. Previews are per task.
class NoteBackgroundStore {
  NoteBackgroundStore({Future<Directory> Function()? support})
    : _support = support ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _support;

  Future<Directory> _dir(String name) async => Directory(
    p.join((await _support()).path, 'note_backgrounds', 'generated', name),
  ).create(recursive: true);

  Future<File> preview(String taskId) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]{8,80}$').hasMatch(taskId)) {
      throw const FormatException('Invalid task');
    }
    return File(p.join((await _dir('previews')).path, '$taskId.png'));
  }

  Future<void> savePreview(String taskId, Uint8List png) async {
    final file = await preview(taskId);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(png, flush: true);
    await temporary.rename(file.path);
  }

  Future<void> deletePreview(String taskId) async {
    final file = await preview(taskId);
    if (await file.exists()) await file.delete();
  }

  /// Moves an accepted preview to a permanent app-owned file and records
  /// what it replaces. Returns the new background map.
  Future<Map<String, dynamic>> accept(
    String taskId,
    String noteId,
    Map<String, dynamic> previous,
  ) async {
    final source = await preview(taskId);
    final target = p.join((await _dir('')).path, '${const Uuid().v4()}.png');
    await source.copy(target);
    final accepted = {...previous, 'image': target, 'image_source': 'local'};
    await File('$target.previous.json').writeAsString(
      jsonEncode({
        'noteId': noteId,
        'previous': previous,
        'accepted': accepted,
      }),
      flush: true,
    );
    return accepted;
  }

  /// The recovery record when [background] is a generated image of [noteId].
  Future<NoteBackgroundRecovery?> recovery(
    String noteId,
    Map<String, dynamic> background,
  ) async {
    final image = background['image'];
    if (image is! String) return null;
    try {
      final dir = (await _dir('')).path;
      if (!p.isWithin(dir, p.normalize(image))) return null;
      final json = jsonDecode(
        await File('$image.previous.json').readAsString(),
      );
      if (json is! Map ||
          json['noteId'] != noteId ||
          json['previous'] is! Map ||
          json['accepted'] is! Map) {
        return null;
      }
      return NoteBackgroundRecovery(
        noteId: noteId,
        previous: (json['previous'] as Map).cast<String, dynamic>(),
        accepted: (json['accepted'] as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Deletes previews older than [noteBackgroundPreviewLifetime], except [keep].
  Future<void> sweepPreviews({String? keep}) async {
    final cutoff = DateTime.now().subtract(noteBackgroundPreviewLifetime);
    await for (final entity in (await _dir('previews')).list()) {
      if (entity is! File ||
          (keep != null && p.basename(entity.path).startsWith(keep))) {
        continue;
      }
      if ((await entity.stat()).modified.isBefore(cutoff)) {
        await entity.delete();
      }
    }
  }
}
