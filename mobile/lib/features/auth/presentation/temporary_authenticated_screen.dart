import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import 'auth_controller.dart';

/// Phase 4B development boundary. Replace with the real Home in a later phase.
class TemporaryAuthenticatedScreen extends StatelessWidget {
  const TemporaryAuthenticatedScreen({required this.controller, super.key});
  final AuthController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sesión iniciada',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (controller.session?.email case final email?) Text(email),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Pantalla temporal de desarrollo · Phase 4B. El inicio según tu rol se implementará en una fase posterior.',
            ),
            const SizedBox(height: AppSpacing.section),
            if (controller.message case final message?)
              Semantics(liveRegion: true, child: Text(message)),
            AppButton(
              label: 'Cerrar sesión',
              isLoading: controller.signingOut,
              onPressed: controller.signOut,
            ),
          ],
        ),
      ),
    ),
  );
}
