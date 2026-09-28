import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_icons.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_sizes.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../domain/certificate_repository.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({required this.validity, this.compact = false, super.key});
  final CertificateValidity validity;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final (label, icon, color, background) = switch (validity) {
      CertificateValidity.valid => (
        'Válido',
        AppIcons.valid,
        AppColors.successText,
        AppColors.successLight,
      ),
      CertificateValidity.revoked => (
        'Revocado',
        AppIcons.revoked,
        AppColors.errorText,
        AppColors.errorLight,
      ),
      CertificateValidity.expired => (
        'Expirado',
        AppIcons.time,
        AppColors.textSecondary,
        AppColors.background,
      ),
    };
    return Semantics(
      label: 'Vigencia: $label',
      child: ExcludeSemantics(
        child: Container(
          padding: compact
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
          decoration: BoxDecoration(
            color: compact ? null : background,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: AppSizes.iconSmall, color: color),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: AppTypography.caption.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
