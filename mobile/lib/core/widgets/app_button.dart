import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radius.dart';
import '../../app/theme/app_sizes.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

enum AppButtonStyle { primary, outline, ghost }

class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.style = AppButtonStyle.primary,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final AppButtonStyle style;

  @override
  Widget build(BuildContext context) {
    final filled = style == AppButtonStyle.primary;
    final foreground = filled ? AppColors.surface : AppColors.brandPrimaryDark;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSizes.button),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          color: filled
              ? (onPressed == null
                    ? AppColors.background
                    : AppColors.brandPrimary)
              : AppColors.surface,
          border: style == AppButtonStyle.outline
              ? Border.all(color: AppColors.border)
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            onTap: isLoading ? null : onPressed,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                child: Semantics(
                  button: true,
                  enabled: !isLoading && onPressed != null,
                  label: isLoading ? '$label. En curso' : label,
                  liveRegion: isLoading,
                  child: ExcludeSemantics(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Opacity(
                          opacity: isLoading ? 0 : 1,
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: AppTypography.button.copyWith(
                              color: onPressed == null
                                  ? AppColors.textSecondary
                                  : foreground,
                            ),
                          ),
                        ),
                        if (isLoading)
                          SizedBox.square(
                            dimension: AppSizes.iconSmall,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: foreground,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
