import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// App-owned copies of diary photos, kept under `<support>/diary_photos`.
///
/// Picker files are temporary and belong to the system, so a story keeps its
/// own copy and never touches the source. Only paths inside [folder] are ever
/// resolved or deleted; synced records naming anything else are ignored.
/// Copies stay on this device: sync shares the records, not the bytes.
class DiaryPhotoStore {
  DiaryPhotoStore({Future<Directory> Function()? supportDirectory})
    : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  /// Replaced in tests; widgets on the paper read it without Riverpod.
  static DiaryPhotoStore instance = DiaryPhotoStore();

  static const folder = 'diary_photos';

  final Future<Directory> Function() _supportDirectory;
  Future<Directory>? _support;

  Future<Directory> get _root => _support ??= _supportDirectory();

  /// Whether [path] is a well-formed name for an app-owned copy.
  static bool isOwned(String path) {
    final parts = p.posix.split(path);
    return parts.length == 2 &&
        parts.first == folder &&
        parts.last == p.posix.basename(parts.last) &&
        !parts.last.startsWith('.') &&
        !path.contains('\\');
  }

  Future<File?> resolve(String path) async {
    if (!isOwned(path)) return null;
    final root = await _root;
    return File(p.joinAll([root.path, ...p.posix.split(path)]));
  }

  /// The saved bytes, or null when the copy isn't on this device.
  Future<Uint8List?> read(String path) async {
    final file = await resolve(path);
    if (file == null) return null;
    try {
      final bytes = await file.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } on FileSystemException {
      return null;
    }
  }

  /// Writes a private copy and returns its relative path.
  Future<String> write(
    String id,
    Uint8List bytes, {
    String extension = '',
  }) async {
    final ext = RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(extension.toLowerCase())
        ? extension.toLowerCase()
        : '.jpg';
    final path = p.posix.join(folder, '$id$ext');
    final file = (await resolve(path))!;
    await file.parent.create(recursive: true);
    // Write beside it first so a crash never leaves a truncated photo.
    final partial = File('${file.path}.partial');
    await partial.writeAsBytes(bytes, flush: true);
    await partial.rename(file.path);
    return path;
  }

  /// Deletes app-owned copies; anything else is left alone.
  Future<void> delete(Iterable<String> paths) async {
    for (final path in paths) {
      final file = await resolve(path);
      try {
        if (file != null && await file.exists()) await file.delete();
      } on FileSystemException {
        // A copy that can't be removed now is cleared by account reset.
      }
    }
  }

  static Future<String> digest(Uint8List bytes) async {
    final hash = await Sha256().hash(bytes);
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
