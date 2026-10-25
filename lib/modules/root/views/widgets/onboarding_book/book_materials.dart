import 'dart:ui' as ui;

import 'package:flutter/material.dart';

const bookPaperEdgeAsset = 'assets/images/onboarding/paper-edge.webp';
const bookBindingAsset = 'assets/images/onboarding/binding-cloth.webp';
const bookMaterialProviders = [
  ResizeImage(AssetImage(bookPaperEdgeAsset), width: 1024),
  ResizeImage(AssetImage(bookBindingAsset), width: 192),
];

/// Keep the small material images in Flutter's cache and own the image handles
/// used by the painters. The fallback geometry is also usable while decoding.
class BookMaterials extends StatefulWidget {
  const BookMaterials({super.key, required this.builder});

  final Widget Function(
    BuildContext context,
    ui.Image? paper,
    ui.Image? binding,
  )
  builder;

  @override
  State<BookMaterials> createState() => _BookMaterialsState();
}

class _BookMaterialsState extends State<BookMaterials> {
  final _streams = <ImageStream?>[null, null];
  final _images = <ImageInfo?>[null, null];
  late final _listeners = List.generate(
    2,
    (index) => ImageStreamListener((image, synchronousCall) {
      final previous = _images[index];
      setState(() => _images[index] = image);
      if (previous != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
      }
    }),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final configuration = createLocalImageConfiguration(context);
    for (var index = 0; index < bookMaterialProviders.length; index++) {
      final stream = bookMaterialProviders[index].resolve(configuration);
      if (stream.key == _streams[index]?.key) continue;
      _streams[index]?.removeListener(_listeners[index]);
      _streams[index] = stream;
      stream.addListener(_listeners[index]);
    }
  }

  @override
  void dispose() {
    for (var index = 0; index < _streams.length; index++) {
      _streams[index]?.removeListener(_listeners[index]);
      _images[index]?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _images[0]?.image, _images[1]?.image);
}
