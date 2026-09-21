import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/certichain_logo.dart';

class AuthBrand extends StatelessWidget {
  const AuthBrand({super.key});

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      CertiChainLogo(size: AppSpacing.large),
      SizedBox(width: AppSpacing.sm),
      Flexible(child: Text('CertiChain', style: AppTypography.h2)),
    ],
  );
}
