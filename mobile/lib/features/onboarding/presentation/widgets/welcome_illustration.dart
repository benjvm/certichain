import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_shadows.dart';
import '../../../../app/theme/app_spacing.dart';

// TODO: Replace this vector placeholder with the final certificate artwork.
class WelcomeIllustration extends StatelessWidget {
  const WelcomeIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Certificado protegido por un escudo',
      image: true,
      child: SizedBox(
        width: 280,
        height: 245,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 250,
              height: 205,
              decoration: BoxDecoration(
                color: AppColors.brandPrimaryLight,
                borderRadius: BorderRadius.circular(
                  AppRadius.xxl + AppRadius.xxl,
                ),
              ),
            ),
            Positioned(
              left: 22,
              bottom: 26,
              child: Transform.rotate(
                angle: -0.10,
                child: Container(
                  width: 177,
                  height: 130,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    boxShadow: AppShadows.level2,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.workspace_premium_rounded,
                        size: 24,
                        color: AppColors.brandPrimary,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _line(120, AppColors.brandPrimaryLight),
                      const SizedBox(height: AppSpacing.sm),
                      _line(94, AppColors.border),
                      const SizedBox(height: AppSpacing.sm),
                      _line(72, AppColors.border),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 30,
              right: 23,
              child: Transform.rotate(
                angle: 0.08,
                child: Container(
                  width: 166,
                  height: 85,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        AppColors.brandPrimary,
                        AppColors.brandPrimaryDark,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    boxShadow: AppShadows.level2,
                  ),
                  child: const Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Icon(
                        Icons.verified_outlined,
                        color: AppColors.surface,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Positioned(right: 23, bottom: 8, child: _Shield()),
          ],
        ),
      ),
    );
  }

  Widget _line(double width, Color color) => Container(
    width: width,
    height: 6,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(AppRadius.pill),
    ),
  );
}

class _Shield extends StatelessWidget {
  const _Shield();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 88,
      decoration: const BoxDecoration(
        color: AppColors.brandPrimary,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        boxShadow: AppShadows.level2,
      ),
      child: const Icon(
        Icons.check_rounded,
        color: AppColors.surface,
        size: 42,
      ),
    );
  }
}
