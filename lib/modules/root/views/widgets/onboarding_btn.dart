import 'package:journal/common.dart';

class OnboardingPrimaryButton extends StatelessWidget {
  const OnboardingPrimaryButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 58),
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(32),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFB4A5BB), Color(0xFFC4B8CA), Color(0xFFA89582)],
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x2165503B),
          blurRadius: 18,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFAF8FF), Color(0xFFDFDAFF)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .65)),
      ),
      child: OnboardingAction(
        onTap: onPressed,
        feedbackColor: AppThemeConfig.primaryColor,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              const SizedBox(width: 36),
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppThemeConfig.primaryColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .1,
                  ),
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppThemeConfig.primaryColor.withValues(alpha: .08),
                ),
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  color: AppThemeConfig.primaryColor,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class OnboardingAction extends StatelessWidget {
  const OnboardingAction({
    required this.onTap,
    required this.feedbackColor,
    required this.child,
    super.key,
  });

  final VoidCallback? onTap;
  final Color feedbackColor;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    borderRadius: BorderRadius.circular(30),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      splashColor: feedbackColor.withValues(alpha: .18),
      highlightColor: feedbackColor.withValues(alpha: .08),
      hoverColor: feedbackColor.withValues(alpha: .06),
      focusColor: feedbackColor.withValues(alpha: .12),
      child: child,
    ),
  );
}
