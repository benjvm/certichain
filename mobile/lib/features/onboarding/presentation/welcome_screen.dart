import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/router/app_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/certichain_logo.dart';
import 'widgets/welcome_illustration.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, this.onStart});

  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenHorizontal,
                    vertical: AppSpacing.xxl,
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        height: math.min(
                          constraints.maxHeight * 0.10,
                          AppSpacing.huge,
                        ),
                      ),
                      const CertiChainLogo(),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'CertiChain',
                        style: AppTypography.h1,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Certificados digitales,\nverificables y seguros',
                        style: AppTypography.body.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const Spacer(),
                      const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: WelcomeIllustration(),
                      ),
                      const Spacer(),
                      const _PageIndicator(),
                      const SizedBox(height: AppSpacing.large),
                      SizedBox(
                        width: double.infinity,
                        child: AppButton(
                          label: 'Comenzar',
                          onPressed: onStart ?? () => _startNextPhase(context),
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
    );
  }

  void _startNextPhase(BuildContext context) {
    Navigator.of(context).pushNamed(AppRouter.loginRoute);
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Página 1 de 3',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          3,
          (index) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: index == 0 ? AppColors.brandPrimary : AppColors.border,
                shape: BoxShape.circle,
              ),
              child: const SizedBox(width: 8, height: 8),
            ),
          ),
        ),
      ),
    );
  }
}
