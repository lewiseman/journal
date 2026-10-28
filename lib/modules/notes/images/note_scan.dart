import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// I04: transcribe a photographed or scanned page into editable text.
const noteScanOperation = 'scan-note-image';
const noteScanContract = 1;
const noteScanOutputBytes = 12288;
const noteScanTextChars = 6000;

/// The exact prompt for every scan; the image is the only other input.
const noteScanPrompt = '{"mode":"transcribe"}';

/// What a scan request was made from. Kept in protected task storage.
class NoteScanRequest {
  const NoteScanRequest({
    required this.noteId,
    required this.version,
    required this.path,
    required this.imageSha,
  });
  final String noteId, version, path, imageSha;

  String encode() => jsonEncode({
    'noteId': noteId,
    'version': version,
    'path': path,
    'imageSha': imageSha,
  });
  factory NoteScanRequest.decode(String raw) {
    final json = jsonDecode(raw);
    if (json is! Map ||
        [
          'noteId',
          'version',
          'path',
          'imageSha',
        ].any((k) => json[k] is! String) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(json['imageSha'] as String)) {
      throw const FormatException('Invalid scan request');
    }
    return NoteScanRequest(
      noteId: json['noteId'] as String,
      version: json['version'] as String,
      path: json['path'] as String,
      imageSha: json['imageSha'] as String,
    );
  }
}

class NoteScanCheckLine {
  const NoteScanCheckLine(this.text, this.confidence);
  final String text;
  final double confidence;
}

/// A validated transcription. [check] is an independent EasyOCR reading,
/// or null when the computer has no second reader.
class NoteScanResult {
  const NoteScanResult({
    required this.text,
    required this.readable,
    required this.check,
  });
  final String text;
  final bool readable;
  final List<NoteScanCheckLine>? check;

  factory NoteScanResult.parse(String raw) {
    final json = jsonDecode(raw);
    final control = RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');
    if (json is! Map ||
        json.length != 3 ||
        json['text'] is! String ||
        json['readable'] is! bool ||
        (json['text'] as String).runes.length > noteScanTextChars ||
        control.hasMatch(json['text'] as String) ||
        (json['check'] != null && json['check'] is! List)) {
      throw const FormatException('Invalid scan result');
    }
    List<NoteScanCheckLine>? check;
    if (json['check'] case final List lines) {
      check = [
        for (final line in lines)
          if (line is Map &&
              line['text'] is String &&
              line['confidence'] is num &&
              !control.hasMatch(line['text'] as String))
            NoteScanCheckLine(
              line['text'] as String,
              (line['confidence'] as num).toDouble().clamp(0, 1),
            )
          else
            throw const FormatException('Invalid check line'),
      ];
    }
    return NoteScanResult(
      text: (json['text'] as String).trim(),
      readable: json['readable'] as bool,
      check: check,
    );
  }

  bool get empty => text.replaceAll('[?]', '').trim().isEmpty;

  /// Places the reader marked as unreadable.
  int get unreadableMarks => '[?]'.allMatches(text).length;

  /// Words most costly to get wrong (containing digits, or capitalised mid
  /// line, e.g. names) that the second reader did not read the same way.
  /// Empty when there is no second reader; nothing is ever changed.
  List<String> get disagreements {
    final checkLines = check;
    if (checkLines == null) return const [];
    final seen = {
      for (final line in checkLines)
        for (final word in _words(line.text)) _key(word),
    };
    final flagged = <String>{};
    for (final line in text.split('\n')) {
      final words = _words(line);
      for (final (i, word) in words.indexed) {
        final risky =
            word.contains(RegExp(r'\d')) ||
            (i > 0 && RegExp(r'^\p{Lu}', unicode: true).hasMatch(word));
        if (risky && !seen.contains(_key(word))) flagged.add(word);
      }
    }
    return flagged.toList();
  }

  static List<String> _words(String line) => [
    for (final word in line.split(RegExp(r'\s+')))
      if (_key(word).isNotEmpty)
        word.replaceAll(RegExp(r'''^[("'“‘]+|[)"'”’.,;:!?]+$'''), ''),
  ];

  /// Case-insensitive, ignoring surrounding punctuation only: "3:15pm" and
  /// "315pm" differ.
  static String _key(String word) => word.toLowerCase().replaceAll(
    RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true),
    '',
  );
}

final noteScanStoreProvider = Provider<NoteScanStore>((ref) => NoteScanStore());

/// App-owned scan copies in `<support>/note_scans`. The picked source is
/// never modified. Each attached scan keeps its original transcription in a
/// sidecar so a corrected note can be compared with what was read.
class NoteScanStore {
  NoteScanStore({Future<Directory> Function()? support})
    : _support = support ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _support;

  Future<Directory> directory() async {
    final support = await _support();
    return Directory(p.join(support.path, 'note_scans'))
        .create(recursive: true);
  }

  Future<bool> owns(String path) async =>
      p.isWithin((await directory()).path, p.normalize(path));

  /// Copies a picked file into app storage and returns the copy's path.
  Future<String> import(String source) async {
    final dir = await directory();
    final extension = p.extension(source).toLowerCase();
    final target = p.join(
      dir.path,
      '${const Uuid().v4()}${RegExp(r'^\.(jpe?g|png|heic|heif|webp)$').hasMatch(extension) ? extension : '.img'}',
    );
    await File(source).copy(target);
    return target;
  }

  /// Writes a copy turned 90° clockwise and removes [path].
  Future<String> rotate(String path) async {
    if (!await owns(path)) {
      throw StateError('Only app-owned scans can be rotated.');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      await File(path).readAsBytes(),
    );
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final scale = math.min(
      1.0,
      2400 / math.max(descriptor.width, descriptor.height),
    );
    final codec = await descriptor.instantiateCodec(
      targetWidth: (descriptor.width * scale).round(),
      targetHeight: (descriptor.height * scale).round(),
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..translate(image.height.toDouble(), 0)
      ..rotate(math.pi / 2)
      ..drawImage(image, ui.Offset.zero, ui.Paint());
    final rotated = await recorder.endRecording().toImage(
      image.height,
      image.width,
    );
    final data = await rotated.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    rotated.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    final target = p.join(p.dirname(path), '${const Uuid().v4()}.png');
    await File(target).writeAsBytes(data!.buffer.asUint8List(), flush: true);
    await delete(path);
    return target;
  }

  Future<void> delete(String path) async {
    if (!await owns(path)) return;
    for (final file in [File(path), File('$path.json')]) {
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> writeOriginal(String path, String noteId, String text) async {
    if (!await owns(path)) {
      throw StateError('Only app-owned scans keep originals.');
    }
    await File('$path.json').writeAsString(
      jsonEncode({
        'noteId': noteId,
        'text': text,
        'created': DateTime.now().millisecondsSinceEpoch,
      }),
      flush: true,
    );
  }

  Future<String?> readOriginal(String path) async {
    try {
      final json = jsonDecode(await File('$path.json').readAsString());
      return json is Map && json['text'] is String
          ? json['text'] as String
          : null;
    } catch (_) {
      return null;
    }
  }

  /// Removes scans no note references, except [keep] (an unsaved scan).
  Future<void> sweep(
    Set<String> referenced, {
    Set<String> keep = const {},
  }) async {
    final dir = await directory();
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final image = entity.path.endsWith('.json')
          ? entity.path.substring(0, entity.path.length - 5)
          : entity.path;
      if (referenced.contains(image) || keep.contains(image)) continue;
      // A day's grace covers a scan picked but not yet read or inserted.
      if ((await entity.stat()).modified.isAfter(cutoff)) continue;
      await entity.delete();
    }
  }
}
