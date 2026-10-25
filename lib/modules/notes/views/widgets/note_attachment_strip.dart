import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/note_attachment_service.dart';
import '../../models/note_attachment.dart';
import '../../models/note_colors.dart';

class NoteAttachmentStrip extends StatelessWidget {
  const NoteAttachmentStrip({
    super.key,
    required this.attachments,
    required this.colors,
    this.onRemove,
  });

  final List<Map<String, dynamic>> attachments;
  final NoteColors colors;
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) {
    final entries = [
      for (var i = 0; i < attachments.length; i++)
        if (NoteAttachment.tryFromMap(attachments[i]) case final attachment?)
          (index: i, attachment: attachment),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();
    final scaler = MediaQuery.textScalerOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          height: 116 + scaler.scale(14) * 1.3 + scaler.scale(11) * 1.3,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return SizedBox(
                width: math.min(172, constraints.maxWidth),
                child: _AttachmentCard(
                  key: ValueKey((entry.index, entry.attachment.path)),
                  attachment: entry.attachment,
                  colors: colors,
                  onRemove: onRemove == null
                      ? null
                      : () => onRemove!(entry.index),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AttachmentCard extends ConsumerStatefulWidget {
  const _AttachmentCard({
    super.key,
    required this.attachment,
    required this.colors,
    this.onRemove,
  });

  final NoteAttachment attachment;
  final NoteColors colors;
  final VoidCallback? onRemove;

  @override
  ConsumerState<_AttachmentCard> createState() => _AttachmentCardState();
}

class _AttachmentCardState extends ConsumerState<_AttachmentCard> {
  late Future<bool> _available = ref
      .read(noteAttachmentServiceProvider)
      .isAvailable(widget.attachment);
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final service = ref.read(noteAttachmentServiceProvider);
      final error = await service.open(widget.attachment);
      if (mounted && error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      }
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
          _available = ref
              .read(noteAttachmentServiceProvider)
              .isAvailable(widget.attachment);
        });
      }
    }
  }

  IconData get _fileIcon => switch (widget.attachment.type) {
    'application/pdf' => Icons.picture_as_pdf_outlined,
    final type when type.startsWith('audio/') => Icons.audio_file_outlined,
    final type when type.startsWith('video/') => Icons.video_file_outlined,
    final type when type.startsWith('text/') => Icons.description_outlined,
    _ => Icons.insert_drive_file_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final attachment = widget.attachment;
    final ink = widget.colors.foreground;
    final fill = Color.alphaBlend(
      ink.withValues(alpha: .05),
      widget.colors.background,
    );
    return Material(
      color: fill,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: ink.withValues(alpha: .15)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Semantics(
              label: 'Open ${attachment.filename}',
              button: true,
              child: InkWell(
                onTap: _opening ? null : _open,
                child: FutureBuilder<bool>(
                  future: _available,
                  builder: (context, snapshot) {
                    final unavailable = snapshot.data == false;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: attachment.isImage && !unavailable
                              ? Image.file(
                                  attachment.file,
                                  fit: BoxFit.cover,
                                  cacheWidth: 512,
                                  excludeFromSemantics: true,
                                  errorBuilder: (_, _, _) =>
                                      _placeholder(ink, true),
                                )
                              : _placeholder(ink, unavailable),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                attachment.filename,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: ink,
                                  fontSize: 14,
                                  height: 1.3,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                unavailable
                                    ? 'Unavailable'
                                    : attachment.typeLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: ink.withValues(alpha: .7),
                                  fontSize: 11,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          if (widget.onRemove != null)
            PositionedDirectional(
              top: 0,
              end: 0,
              child: IconButton(
                tooltip: 'Remove ${attachment.filename}',
                onPressed: widget.onRemove,
                style: IconButton.styleFrom(
                  foregroundColor: ink,
                  backgroundColor: fill,
                ),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder(Color ink, bool unavailable) => Center(
    child: Icon(
      unavailable
          ? widget.attachment.isImage
                ? Icons.broken_image_outlined
                : Icons.error_outline_rounded
          : _fileIcon,
      semanticLabel: unavailable ? 'Attachment unavailable' : null,
      size: 36,
      color: ink.withValues(alpha: .65),
    ),
  );
}
