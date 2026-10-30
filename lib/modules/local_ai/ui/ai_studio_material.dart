import 'package:flutter/material.dart';

TextStyle studioTitle(BuildContext context, {double size = 25}) =>
    Theme.of(context).textTheme.titleLarge!.copyWith(
      fontSize: size,
      color: Theme.of(context).colorScheme.onSurface,
      fontWeight: FontWeight.w600,
      height: 1.25,
    );

/// A flat settings card without paper textures or painted shadows.
class AiStudioCard extends StatelessWidget {
  const AiStudioCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: color ?? colors.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: Padding(padding: padding, child: child),
            ),
    );
  }
}

class AiStudioSectionHeading extends StatelessWidget {
  const AiStudioSectionHeading({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
