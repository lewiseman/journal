import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:journal/modules/notes/models/note_attachment.dart';
import 'package:journal/modules/notes/models/note_entity.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';

/// I03: one bounded question about one image attached to a saved note.
const noteImageOperation = 'ask-note-image';
const noteImageContract = 1;
const noteImageQuestionChars = 300;
const noteImageOutputBytes = 4096;

/// Source files above this are not read at all.
const noteImageSourceBytes = 40 * 1024 * 1024;

/// Upload budget after re-encoding; the desktop accepts up to 3 MiB.
const noteImageUploadBytes = 2560 * 1024;
const _sides = [1280, 1024, 896, 768];

const noteImageModes = {
  'describe': 'Describe',
  'explain': 'Explain',
  'question': 'Ask a question',
};

final _control = RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');

/// What was asked, and about which exact attachment and note version. Kept in
/// protected task storage; only [mode], [question] and the re-encoded image
/// are sent.
class NoteImageRequest {
  const NoteImageRequest({
    required this.noteId,
    required this.version,
    required this.path,
    required this.mode,
    required this.question,
    required this.imageSha,
  });
  final String noteId, version, path, mode, question;

  /// SHA-256 of the re-encoded upload, so a retry sends identical bytes.
  final String imageSha;

  String request() => jsonEncode({'mode': mode, 'question': question});

  String encode() => jsonEncode({
    'noteId': noteId,
    'version': version,
    'path': path,
    'mode': mode,
    'question': question,
    'imageSha': imageSha,
  });
  factory NoteImageRequest.decode(String raw) {
    final json = jsonDecode(raw);
    if (json is! Map ||
        [
          'noteId',
          'version',
          'path',
          'mode',
          'question',
          'imageSha',
        ].any((k) => json[k] is! String) ||
        !noteImageModes.containsKey(json['mode']) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(json['imageSha'] as String)) {
      throw const FormatException('Invalid image source');
    }
    return NoteImageRequest(
      noteId: json['noteId'] as String,
      version: json['version'] as String,
      path: json['path'] as String,
      mode: json['mode'] as String,
      question: json['question'] as String,
      imageSha: json['imageSha'] as String,
    );
  }

  /// Throws [FormatException] for an invalid mode/question combination.
  static void validate(String mode, String question) {
    if (!noteImageModes.containsKey(mode) ||
        (mode == 'question') != question.trim().isNotEmpty ||
        question.runes.length > noteImageQuestionChars ||
        _control.hasMatch(question)) {
      throw const FormatException(
        'Ask a question of at most 300 characters, or choose Describe or Explain.',
      );
    }
  }
}

/// The attachment, if [path] is still one of [note]'s image attachments.
NoteAttachment? noteImageAttachment(NoteEntity? note, String path) {
  if (note == null || note.isDeleted || note.isPermanentlyDeleted) return null;
  for (final entry in note.attachments) {
    final attachment = NoteAttachment.tryFromMap(entry);
    if (attachment != null && attachment.isImage && attachment.path == path) {
      return attachment;
    }
  }
  return null;
}

/// Reads one attached image and re-encodes it as PNG at most 1280 px on its
/// long side. Re-encoding drops EXIF/location metadata and anything appended
/// to the file. Throws [CompanionFailure] with a user-facing message.
Future<Uint8List> prepareNoteImage(NoteAttachment attachment) async {
  final file = attachment.file;
  final FileStat stat;
  try {
    stat = await file.stat();
  } catch (_) {
    throw _missing;
  }
  if (stat.type == FileSystemEntityType.notFound) throw _missing;
  if (stat.type != FileSystemEntityType.file) {
    throw const CompanionFailure(
      'INVALID_IMAGE',
      'This attachment is not a regular image file on this phone.',
    );
  }
  if (stat.size > noteImageSourceBytes || stat.size == 0) {
    throw const CompanionFailure(
      'INVALID_IMAGE',
      'This image is empty or larger than 40 MB. Nothing was sent.',
    );
  }
  final Uint8List bytes;
  try {
    bytes = await file.readAsBytes();
  } catch (_) {
    throw _missing;
  }
  return prepareImageBytes(bytes);
}

/// Re-encodes in-memory image [bytes] the same way as [prepareNoteImage].
Future<Uint8List> prepareImageBytes(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > noteImageSourceBytes) {
    throw const CompanionFailure(
      'INVALID_IMAGE',
      'This image is empty or larger than 40 MB. Nothing was sent.',
    );
  }
  if (!_looksLikeImage(bytes)) {
    throw const CompanionFailure(
      'INVALID_IMAGE',
      'This file is not a supported image (JPEG, PNG, WebP, GIF or HEIC). Nothing was sent.',
    );
  }
  for (final side in _sides) {
    final png = await _encode(bytes, side);
    if (png.length <= noteImageUploadBytes) return png;
  }
  throw const CompanionFailure(
    'INVALID_IMAGE',
    'This image is too detailed to send within the size limit. Nothing was sent.',
  );
}

const _missing = CompanionFailure(
  'IMAGE_MISSING',
  'This image is not available on this phone. Attachments restored from another device or Drive keep only their path; reattach the image here to ask about it.',
);

bool _looksLikeImage(Uint8List b) {
  bool starts(List<int> sig, [int offset = 0]) =>
      b.length >= offset + sig.length &&
      [for (var i = 0; i < sig.length; i++) b[offset + i] == sig[i]]
          .every((x) => x);
  return starts([0xff, 0xd8, 0xff]) ||
      starts([0x89, 0x50, 0x4e, 0x47]) ||
      starts([0x47, 0x49, 0x46, 0x38]) ||
      (starts([0x52, 0x49, 0x46, 0x46]) &&
          starts([0x57, 0x45, 0x42, 0x50], 8)) ||
      starts([0x66, 0x74, 0x79, 0x70], 4);
}

Future<Uint8List> _encode(Uint8List bytes, int side) async {
  final ui.ImmutableBuffer buffer;
  final ui.ImageDescriptor descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
  } catch (_) {
    throw const CompanionFailure(
      'INVALID_IMAGE',
      'This image could not be decoded on this phone. Nothing was sent.',
    );
  }
  final scale =
      side /
      (descriptor.width > descriptor.height
          ? descriptor.width
          : descriptor.height);
  final codec = await descriptor.instantiateCodec(
    targetWidth: scale < 1 ? (descriptor.width * scale).round() : null,
    targetHeight: scale < 1 ? (descriptor.height * scale).round() : null,
  );
  try {
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    if (data == null) throw const FormatException();
    return data.buffer.asUint8List();
  } catch (_) {
    throw const CompanionFailure(
      'INVALID_IMAGE',
      'This image could not be prepared on this phone. Nothing was sent.',
    );
  } finally {
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
  }
}

/// A validated answer. Each part is shown separately so visible evidence,
/// text read from the image and interpretation are never mixed.
class NoteImageAnswer {
  const NoteImageAnswer({
    required this.observations,
    required this.text,
    required this.inference,
    required this.answer,
  });
  final String observations, text, inference, answer;

  factory NoteImageAnswer.parse(String raw) {
    final json = jsonDecode(raw);
    String field(String key, int max, {bool empty = true}) {
      final value = json is Map ? json[key] : null;
      if (value is! String ||
          (!empty && value.trim().isEmpty) ||
          value.runes.length > max ||
          _control.hasMatch(value)) {
        throw const FormatException('Invalid image answer');
      }
      return value.trim();
    }

    if (json is! Map || json.length != 4) {
      throw const FormatException('Invalid image answer');
    }
    final inference = field('inference', 500);
    final text = field('text', 900);
    // The model sometimes repeats the "cannot answer" phrase in other fields.
    const unanswerable = 'The image does not show this.';
    return NoteImageAnswer(
      observations: field('observations', 900, empty: false),
      text: text == unanswerable ? '' : text,
      inference: inference,
      answer: field('answer', 600),
    );
  }

  /// The default text offered for insertion: the answer, else observations.
  String get insertion => answer.isNotEmpty ? answer : observations;
}
