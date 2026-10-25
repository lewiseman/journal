import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../models/note_attachment.dart';

final noteAttachmentServiceProvider = Provider<NoteAttachmentService>(
  (ref) => NoteAttachmentService(),
);

class NoteAttachmentSelection {
  const NoteAttachmentSelection({
    this.attachments = const [],
    this.skipped = 0,
  });

  final List<NoteAttachment> attachments;
  final int skipped;
}

class NoteAttachmentService {
  NoteAttachmentService({
    Future<List<PlatformFile>> Function()? picker,
    Future<OpenResult> Function(String path, String type)? opener,
  }) : _picker = picker ?? (() => FilePicker.pickFiles(type: FileType.any)),
       _opener = opener ?? ((path, type) => OpenFilex.open(path, type: type));

  final Future<List<PlatformFile>> Function() _picker;
  final Future<OpenResult> Function(String path, String type) _opener;

  Future<NoteAttachmentSelection> pick() async {
    final files = await _picker();
    final attachments = <NoteAttachment>[];
    var skipped = 0;
    for (final file in files) {
      if (!NoteAttachment.isLocalPath(file.path)) {
        skipped++;
        continue;
      }
      attachments.add(NoteAttachment.fromPath(file.path!));
    }
    return NoteAttachmentSelection(attachments: attachments, skipped: skipped);
  }

  Future<bool> isAvailable(NoteAttachment attachment) async {
    try {
      // Opening without reading checks access without loading large documents.
      final handle = await attachment.file.open();
      await handle.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// A null message indicates success. Native error details stay out of the UI.
  Future<String?> open(NoteAttachment attachment) async {
    if (!await isAvailable(attachment)) return 'This file is unavailable.';
    try {
      final result = await _opener(attachment.file.path, attachment.type);
      return switch (result.type) {
        ResultType.done => null,
        ResultType.fileNotFound => 'This file is unavailable.',
        ResultType.noAppToOpen => 'No installed app can open this file.',
        ResultType.permissionDenied => 'Access to this file was denied.',
        ResultType.error => 'Could not open this file. Please try again.',
      };
    } catch (_) {
      return 'Could not open this file. Please try again.';
    }
  }
}
