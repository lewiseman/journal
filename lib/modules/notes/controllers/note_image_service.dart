import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/note_art.dart';

final noteImageServiceProvider = Provider<NoteImageService>(
  (ref) => NoteImageService(),
);

class NoteImageService {
  NoteImageService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<NoteImagePreset?> pickFromGallery() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    return file == null ? null : _photo(file);
  }

  /// Recovers a picker result after Android recreates the activity.
  Future<NoteImagePreset?> recoverLostImage() async {
    if (!Platform.isAndroid) return null;
    final response = await _picker.retrieveLostData();
    if (response.exception != null) throw response.exception!;
    final files = response.files;
    return files == null || files.isEmpty ? null : _photo(files.first);
  }

  Future<NoteImagePreset> _photo(XFile file) async {
    // Picker files can be temporary. Keep a private copy for saved notes.
    final support = await getApplicationSupportDirectory();
    final directory = await Directory(p.join(support.path, 'note_backgrounds'))
        .create(recursive: true);
    final path = p.join(
      directory.path,
      '${const Uuid().v4()}${p.extension(file.path)}',
    );
    await file.saveTo(path);
    return NoteImagePreset(
      label: 'Your photo',
      url: path,
      source: NoteImageSource.local,
    );
  }
}
