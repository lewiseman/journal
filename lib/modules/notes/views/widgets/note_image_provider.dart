import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart';

import '../../models/note_art.dart';

ImageProvider noteImageProvider(String url, NoteImageSource source) =>
    switch (source) {
      NoteImageSource.remote => CachedNetworkImageProvider(url),
      NoteImageSource.local => FileImage(
        url.startsWith('file:') ? File.fromUri(Uri.parse(url)) : File(url),
      ),
    };
