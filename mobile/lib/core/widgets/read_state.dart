import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_icons.dart';
import '../../app/theme/app_sizes.dart';
import '../../app/theme/app_spacing.dart';

class ReadError extends StatelessWidget {
  const ReadError({required this.message, required this.onRetry, super.key});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => _ReadPanel(
    children: [
      const Icon(
        AppIcons.info,
        color: AppColors.errorText,
        size: AppSizes.iconLarge,
      ),
      const SizedBox(height: AppSpacing.md),
      Semantics(
        liveRegion: true,
        child: Text(message, textAlign: TextAlign.center),
      ),
      TextButton(onPressed: onRetry, child: const Text('Reintentar')),
    ],
  );
}

class ReadLoading extends StatelessWidget {
  const ReadLoading({required this.label, super.key});
  final String label;
  @override
  Widget build(BuildContext context) => _ReadPanel(
    children: [
      Center(
        child: SizedBox.square(
          dimension: AppSizes.iconLarge,
          child: CircularProgressIndicator(semanticsLabel: label),
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      ExcludeSemantics(child: Text(label, textAlign: TextAlign.center)),
    ],
  );
}

class ReadEmpty extends StatelessWidget {
  const ReadEmpty({
    required this.title,
    required this.message,
    this.icon = AppIcons.document,
    super.key,
  });
  final String title;
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => _ReadPanel(
    children: [
      Icon(icon, color: AppColors.brandPrimary, size: AppSizes.iconLarge),
      const SizedBox(height: AppSpacing.md),
      Text(
        title,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: AppColors.textSecondary),
      ),
    ],
  );
}

class _ReadPanel extends StatelessWidget {
  const _ReadPanel({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}
