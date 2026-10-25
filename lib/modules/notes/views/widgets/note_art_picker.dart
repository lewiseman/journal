import 'package:flutter/services.dart';
import 'package:journal/common.dart';
import 'package:journal/modules/notes/controllers/note_image_service.dart';

import 'note_image_provider.dart';

/// Stages a color and an optional image until Apply is pressed.
/// A null route result means cancellation, rather than removing the image.
class NoteArtPicker extends ConsumerStatefulWidget {
  const NoteArtPicker({
    super.key,
    this.scrollController,
    this.currentType,
    this.currentImageUrl,
    this.currentImageSource = NoteImageSource.remote,
  });

  final ScrollController? scrollController;
  final String? currentType;
  final String? currentImageUrl;
  final NoteImageSource currentImageSource;

  static Future<NoteArtSelection?> pick(
    BuildContext context,
    Map<String, dynamic> currentBg,
  ) {
    FocusManager.instance.primaryFocus?.unfocus();
    final current = NoteArtSelection.fromBackground(currentBg);
    return showModalBottomSheet<NoteArtSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      requestFocus: true,
      backgroundColor: context.colors.surface,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      constraints: BoxConstraints(
        maxWidth: 560,
        maxHeight: MediaQuery.sizeOf(context).height * .8,
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 1,
        minChildSize: .5,
        expand: false,
        snap: true,
        builder: (_, scrollController) => NoteArtPicker(
          scrollController: scrollController,
          currentType: current.color.type,
          currentImageUrl: current.imageUrl,
          currentImageSource: current.imageSource,
        ),
      ),
    );
  }

  @override
  ConsumerState<NoteArtPicker> createState() => _NoteArtPickerState();
}

class _NoteArtPickerState extends ConsumerState<NoteArtPicker> {
  late NoteColorPreset _selectedPreset = NoteColors.presetForType(
    widget.currentType,
  );
  late String? _selectedImageUrl = widget.currentImageUrl;
  late NoteImageSource _selectedImageSource = widget.currentImageSource;
  bool _busy = false;
  bool _changedImage = false;
  String? _error;

  // Preserve saved images that are outside the sample catalog.
  late final _images = [
    if (widget.currentImageUrl != null &&
        !NoteImagePreset.samples.any(
          (image) =>
              image.url == widget.currentImageUrl &&
              image.source == widget.currentImageSource,
        ))
      NoteImagePreset(
        label: widget.currentImageSource == NoteImageSource.local
            ? 'Your photo'
            : 'Current image',
        url: widget.currentImageUrl!,
        source: widget.currentImageSource,
      ),
    ...NoteImagePreset.samples,
  ];

  @override
  void initState() {
    super.initState();
    _recoverPhoto();
  }

  Future<void> _recoverPhoto() async {
    try {
      final image = await ref.read(noteImageServiceProvider).recoverLostImage();
      if (!mounted || image == null || _changedImage || _busy) return;
      _usePhoto(image);
    } catch (_) {
      if (!mounted || _changedImage) return;
      setState(() => _error = 'Choose your photo again to restore it.');
    }
  }

  void _usePhoto(NoteImagePreset image) {
    setState(() {
      _images.removeWhere((item) => item.source == NoteImageSource.local);
      _images.insert(0, image);
      _selectedImageUrl = image.url;
      _selectedImageSource = image.source;
      _changedImage = true;
      _error = null;
    });
  }

  Future<void> _pickPhoto() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final image = await ref.read(noteImageServiceProvider).pickFromGallery();
      if (!mounted || image == null) return;
      _usePhoto(image);
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.code == 'photo_access_denied'
            ? 'Allow photo access in Settings to choose a photo.'
            : 'Your photos could not be opened. Please try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = 'Your photos could not be opened. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _apply() {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    Navigator.pop(
      context,
      NoteArtSelection(
        color: _selectedPreset,
        imageUrl: _selectedImageUrl,
        imageSource: _selectedImageSource,
      ),
    );
  }

  void _select(NoteColorPreset preset) {
    if (_busy || _selectedPreset.type == preset.type) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedPreset = preset);
  }

  void _selectImage(NoteImagePreset? image) {
    if (_busy ||
        (_selectedImageUrl == image?.url &&
            (image == null || _selectedImageSource == image.source))) {
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _selectedImageUrl = image?.url;
      _selectedImageSource = image?.source ?? NoteImageSource.remote;
      _changedImage = true;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),

                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final preset in NoteColors.presets)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 12),
                          child: SizedBox(
                            width: MediaQuery.textScalerOf(context).scale(80),
                            child: _ColorOption(
                              preset: preset,
                              selected: preset.type == _selectedPreset.type,
                              duration: duration,
                              onTap: _busy ? null : () => _select(preset),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Text(
                      'Image',
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Optional',
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colors.error,
                        ),
                      ),
                    ),
                  ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final largeText =
                        MediaQuery.textScalerOf(context).scale(14) > 20;
                    final columns = largeText || constraints.maxWidth < 260
                        ? 1
                        : constraints.maxWidth >= 480
                        ? 3
                        : 2;
                    final width =
                        (constraints.maxWidth - 12 * (columns - 1)) / columns;
                    final baseColors = _selectedPreset.resolveColors(colors);
                    final options = [
                      _ImageOption(
                        image: null,
                        selected: _selectedImageUrl == null,
                        baseColors: baseColors,
                        duration: duration,
                        onTap: _busy ? null : () => _selectImage(null),
                      ),
                      _ImageOption.pickLocally(
                        busy: _busy,
                        baseColors: baseColors,
                        duration: duration,
                        onTap: _busy ? null : _pickPhoto,
                      ),
                      for (final image in _images)
                        _ImageOption(
                          image: image,
                          selected:
                              _selectedImageUrl == image.url &&
                              _selectedImageSource == image.source,
                          baseColors: baseColors,
                          duration: duration,
                          onTap: _busy ? null : () => _selectImage(image),
                        ),
                    ];
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final option in options)
                          SizedBox(width: width, child: option),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: colors.outlineVariant.withValues(alpha: .5),
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 24, 16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cancel = TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  );
                  final apply = FilledButton.icon(
                    onPressed: _busy ? null : _apply,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 20),
                    label: const Text('Apply background'),
                  );
                  if (MediaQuery.textScalerOf(context).scale(14) > 20) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [apply, const SizedBox(height: 4), cancel],
                    );
                  }
                  return Row(
                    children: [
                      cancel,
                      const SizedBox(width: 16),
                      Expanded(child: apply),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ColorOption extends StatelessWidget {
  const _ColorOption({
    required this.preset,
    required this.selected,
    required this.duration,
    required this.onTap,
  });

  final NoteColorPreset preset;
  final bool selected;
  final Duration duration;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final palette = preset.resolveColors(colors);
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label: '${preset.label} background, ${preset.description}',
      checked: selected,
      inMutuallyExclusiveGroup: true,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    height: 56,
                    width: 56,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? colors.primary
                            : colors.outlineVariant,
                        width: 1.5,
                      ),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.background,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: AnimatedOpacity(
                          opacity: selected ? 1 : 0,
                          duration: duration,
                          child: Icon(
                            Icons.check_circle_rounded,
                            color: palette.foreground,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    preset.label,
                    textAlign: TextAlign.center,
                    style: textTheme.labelLarge?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageOption extends StatelessWidget {
  const _ImageOption({
    required this.image,
    required this.selected,
    required this.baseColors,
    required this.duration,
    required this.onTap,
  }) : _isPhotoPicker = false,
       busy = false;

  const _ImageOption.pickLocally({
    required this.busy,
    required this.baseColors,
    required this.duration,
    required this.onTap,
  }) : image = null,
       selected = false,
       _isPhotoPicker = true;

  final NoteImagePreset? image;
  final bool selected;
  final bool _isPhotoPicker;
  final bool busy;
  final NoteColors baseColors;
  final Duration duration;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = _isPhotoPicker
        ? (busy ? 'Please wait…' : 'Pick locally')
        : image?.label ?? 'No image';
    return Semantics(
      label: label,
      button: _isPhotoPicker,
      checked: _isPhotoPicker ? null : selected,
      inMutuallyExclusiveGroup: !_isPhotoPicker,
      enabled: onTap != null,
      liveRegion: _isPhotoPicker && busy,
      onTap: onTap,
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: duration,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
              width: 1.5,
            ),
          ),
          child: Material(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: 1.5,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (image == null)
                          ColoredBox(
                            color: baseColors.background,
                            child: Center(
                              child: busy
                                  ? const SizedBox.square(
                                      dimension: 26,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      _isPhotoPicker
                                          ? Icons.add_photo_alternate_outlined
                                          : Icons.hide_image_outlined,
                                      size: 30,
                                      color: baseColors.foreground.withValues(
                                        alpha: .6,
                                      ),
                                    ),
                            ),
                          )
                        else
                          Image(
                            image: ResizeImage.resizeIfNeeded(
                              480,
                              null,
                              noteImageProvider(image!.url, image!.source),
                            ),
                            fit: BoxFit.cover,
                            excludeFromSemantics: true,
                            frameBuilder: (context, child, frame, sync) =>
                                sync || frame != null
                                ? child
                                : const _ImagePlaceholder(),
                            errorBuilder: (context, error, stack) {
                              debugPrint('Unable to load a note image: $error');
                              return const _ImagePlaceholder(unavailable: true);
                            },
                          ),
                        if (selected)
                          PositionedDirectional(
                            top: 8,
                            end: 8,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.check_rounded,
                                  color: colors.onPrimary,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({this.unavailable = false});

  final bool unavailable;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.colors.surfaceContainerHigh,
    child: Center(
      child: Icon(
        unavailable ? Icons.broken_image_outlined : Icons.image_outlined,
        color: context.colors.onSurfaceVariant,
        size: 28,
      ),
    ),
  );
}
