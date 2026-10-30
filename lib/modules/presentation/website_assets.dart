import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:journal/modules/notes/models/note_attachment.dart';

import 'website_themes.dart';

/// The note's photos, in the order a themed website numbers them.
List<NoteAttachment> websitePhotos(List<Map<String, dynamic>> attachments) => [
  for (final value in attachments)
    if (NoteAttachment.tryFromMap(value) case final a? when a.isImage) a,
].take(6).toList();

const _photoSide = 1200;
const _passThroughBytes = 700 * 1024;

/// A photo as a data URI: small JPEG/PNG/WebP files as they are, anything
/// else downscaled to PNG. Null when the file is missing or unreadable.
Future<String?> _photoUri(NoteAttachment photo) async {
  try {
    final bytes = await photo.file.readAsBytes();
    const direct = {'image/jpeg', 'image/png', 'image/webp'};
    if (direct.contains(photo.type) && bytes.length <= _passThroughBytes) {
      return 'data:${photo.type};base64,${base64Encode(bytes)}';
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final longest = descriptor.width > descriptor.height
        ? descriptor.width
        : descriptor.height;
    final scale = longest > _photoSide ? _photoSide / longest : 1.0;
    final codec = await descriptor.instantiateCodec(
      targetWidth: (descriptor.width * scale).round(),
      targetHeight: (descriptor.height * scale).round(),
    );
    try {
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      return data == null
          ? null
          : 'data:image/png;base64,${base64Encode(data.buffer.asUint8List())}';
    } finally {
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  } catch (_) {
    return null;
  }
}

final _cache = <String, String>{};

/// Fills a sanitized page's `data-photo` placeholders with [photos] and
/// embeds the bundled fonts its theme names. Placeholders without a photo on
/// this device are removed. Nothing here is stored or synced.
Future<String> withWebsiteAssets(
  String safe,
  List<NoteAttachment> photos, {
  AssetBundle? bundle,
}) async {
  final document = html.parse(safe);
  final placeholders = document.querySelectorAll('img[data-photo]');
  final theme = document.body?.classes
      .where((c) => c.startsWith('t-'))
      .map((c) => websiteTheme(c.substring(2)))
      .firstOrNull;
  if (placeholders.isEmpty && (theme?.fonts.isEmpty ?? true)) return safe;
  final key = Object.hashAll([safe, for (final p in photos) p.pathKey])
      .toString();
  if (_cache[key] case final cached?) return cached;

  final uris = <int, String?>{};
  for (final img in placeholders) {
    final index = int.tryParse(img.attributes['data-photo'] ?? '');
    final uri = index == null || index < 0 || index >= photos.length
        ? null
        : uris[index] ??= await _photoUri(photos[index]);
    if (uri == null) {
      final parent = img.parent;
      (parent?.localName == 'figure' ? parent! : img).remove();
    } else {
      img.attributes['src'] = uri;
    }
  }
  // An emptied gallery leaves no gap.
  for (final gallery in document.querySelectorAll('.gallery')) {
    if (gallery.children.isEmpty) gallery.remove();
  }

  final faces = StringBuffer();
  for (final family in theme?.fonts ?? const <String>[]) {
    final asset = websiteFontAssets[family];
    if (asset == null) continue;
    try {
      final data = await (bundle ?? rootBundle).load(asset);
      faces.write(
        '@font-face{font-family:"$family";font-display:swap;'
        'src:url(data:font/ttf;base64,'
        '${base64Encode(Uint8List.sublistView(data))}) format("truetype")}',
      );
    } catch (_) {
      // The theme's fallback stack still applies.
    }
  }
  if (faces.isNotEmpty) {
    document.head?.append(dom.Element.tag('style')..text = faces.toString());
  }

  final result = '<!doctype html>\n${document.documentElement!.outerHtml}';
  if (_cache.length >= 4) _cache.remove(_cache.keys.first);
  return _cache[key] = result;
}
