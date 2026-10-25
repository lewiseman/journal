import 'package:flutter/foundation.dart';

import 'note_colors.dart';

enum NoteImageSource { remote, local }

/// The independent color and optional image chosen for a note.
@immutable
class NoteArtSelection {
  const NoteArtSelection({
    required this.color,
    this.imageUrl,
    this.imageSource = NoteImageSource.remote,
  });

  factory NoteArtSelection.fromBackground(Map<String, dynamic> background) {
    final imageUrl = background['image'];
    return NoteArtSelection(
      color: NoteColors.presetForType(background['type']),
      imageUrl: imageUrl is String && imageUrl.trim().isNotEmpty
          ? imageUrl.trim()
          : null,
      imageSource: switch (background['image_source']) {
        'local' => NoteImageSource.local,
        'remote' => NoteImageSource.remote,
        // Older backgrounds only stored a URL. Also accept existing file URIs.
        _ =>
          imageUrl is String &&
                  (imageUrl.trim().startsWith('/') ||
                      imageUrl.trim().startsWith('file:'))
              ? NoteImageSource.local
              : NoteImageSource.remote,
      },
    );
  }

  final NoteColorPreset color;
  final String? imageUrl;
  final NoteImageSource imageSource;

  /// An explicit null clears a previously selected image when merging a draft.
  Map<String, dynamic> toBackground() => {
    'type': color.type,
    'image': imageUrl,
    'image_source': imageUrl == null ? null : imageSource.name,
  };
}

/// Sample network images for the picker; replace this catalog with real art.
@immutable
class NoteImagePreset {
  const NoteImagePreset({
    required this.label,
    required this.url,
    this.source = NoteImageSource.remote,
  });

  final String label;
  final String url;
  final NoteImageSource source;

  static const samples = [
    NoteImagePreset(
      label: 'Open air',
      url: 'https://picsum.photos/id/1018/640/480',
    ),
    NoteImagePreset(
      label: 'Wander',
      url: 'https://picsum.photos/id/1015/640/480',
    ),
    NoteImagePreset(
      label: 'Stillness',
      url: 'https://picsum.photos/id/1016/640/480',
    ),
    NoteImagePreset(
      label: 'Slow morning',
      url: 'https://picsum.photos/id/10/640/480',
    ),
    NoteImagePreset(
      label: 'Daydream',
      url: 'https://picsum.photos/id/29/640/480',
    ),
  ];
}
