import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_icons.dart';
import '../../app/theme/app_sizes.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (index, destination) in const [
              (AppIcons.home, 'Inicio'),
              (AppIcons.certificate, 'Certificados'),
              (AppIcons.profile, 'Perfil'),
            ].indexed)
              Expanded(
                flex:
                    index == 1 && MediaQuery.textScalerOf(context).scale(1) > 1
                    ? 2
                    : 1,
                child: Semantics(
                  button: true,
                  selected: index == selectedIndex,
                  child: InkWell(
                    onTap: () => onSelected(index),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: AppSizes.bottomNavigation,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.md,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              destination.$1,
                              size: AppSizes.icon,
                              color: index == selectedIndex
                                  ? AppColors.brandPrimary
                                  : AppColors.textSecondary,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              destination.$2,
                              textAlign: TextAlign.center,
                              style: AppTypography.navigation.copyWith(
                                color: index == selectedIndex
                                    ? AppColors.brandPrimaryDark
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
