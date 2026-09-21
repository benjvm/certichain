import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';

// Presentation-only preferences, never database roles or authorization claims.
enum RegistrationAccountType { student, institution }

class RegistrationRoleSelector extends StatelessWidget {
  const RegistrationRoleSelector({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final RegistrationAccountType value;
  final ValueChanged<RegistrationAccountType> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('¿Cuál es tu rol?', style: AppTypography.bodyMedium),
      const SizedBox(height: AppSpacing.sm),
      _option(
        RegistrationAccountType.student,
        'Estudiante',
        Icons.school_outlined,
        AppColors.studentAccent,
        AppColors.brandPrimaryLight,
      ),
      const SizedBox(height: AppSpacing.sm),
      _option(
        RegistrationAccountType.institution,
        'Institución',
        Icons.account_balance_outlined,
        AppColors.institutionAccent,
        AppColors.institutionLight,
      ),
      if (value == RegistrationAccountType.institution) ...[
        const SizedBox(height: AppSpacing.sm),
        Text(
          'La institución requiere aprobación para emitir certificados.',
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    ],
  );

  Widget _option(
    RegistrationAccountType type,
    String label,
    IconData icon,
    Color accent,
    Color background,
  ) {
    final selected = value == type;
    return Semantics(
      label: label,
      checked: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: selected ? accent : AppColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => onChanged(type),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  Icon(icon, color: accent),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: Text(label, style: AppTypography.bodyMedium)),
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    selected
                        ? Icons.check_circle_outline
                        : Icons.radio_button_unchecked,
                    color: selected ? accent : AppColors.textSecondary,
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
