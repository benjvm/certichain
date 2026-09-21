import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radius.dart';
import '../../app/theme/app_shadows.dart';
import '../../app/theme/app_typography.dart';

class AppButton extends StatelessWidget {
  const AppButton({required this.label, required this.onPressed, super.key});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          gradient: onPressed == null
              ? null
              : const LinearGradient(
                  colors: [AppColors.brandPrimary, AppColors.brandPrimaryDark],
                ),
          boxShadow: onPressed == null ? null : AppShadows.level1,
        ),
        child: Material(
          color: onPressed == null ? AppColors.disabled : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Text(
                  label,
                  style: AppTypography.label.copyWith(color: AppColors.surface),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
