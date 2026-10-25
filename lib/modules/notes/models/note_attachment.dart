import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

/// An attachment is only a local reference; its contents are never persisted.
class NoteAttachment {
  const NoteAttachment({required this.path, required this.type});

  factory NoteAttachment.fromPath(String path) => NoteAttachment(
    path: path,
    type: lookupMimeType(path) ?? 'application/octet-stream',
  );

  final String path;
  final String type;

  File get file =>
      path.startsWith('file:') ? File.fromUri(Uri.parse(path)) : File(path);

  String get filename => p.basename(file.path);
  String get pathKey => p.normalize(file.path);
  bool get isImage => type.startsWith('image/');
  String get typeLabel {
    final extension = p.extension(filename);
    return extension.isEmpty ? 'FILE' : extension.substring(1).toUpperCase();
  }

  Map<String, dynamic> toMap() => {'path': path, 'type': type};

  /// Older/malformed entries remain stored, even when they cannot be displayed.
  static NoteAttachment? tryFromMap(Map<String, dynamic> value) {
    final path = value['path'];
    if (!isLocalPath(path)) return null;
    final type = value['type'];
    return NoteAttachment(
      path: path as String,
      type: type is String && type.contains('/')
          ? type.toLowerCase()
          : NoteAttachment.fromPath(path).type,
    );
  }

  static bool isLocalPath(Object? value) {
    if (value is! String || value.trim().isEmpty || value.contains('\u0000')) {
      return false;
    }
    try {
      final path = value.startsWith('file:')
          ? File.fromUri(Uri.parse(value)).path
          : value;
      return p.isAbsolute(path);
    } catch (_) {
      return false;
    }
  }
}
