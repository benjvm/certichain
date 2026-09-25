import 'package:flutter/material.dart';

import '../../app/theme/app_spacing.dart';

class ReadError extends StatelessWidget {
  const ReadError({required this.message, required this.onRetry, super.key});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
    child: Column(
      children: [
        Semantics(liveRegion: true, child: Text(message)),
        TextButton(onPressed: onRetry, child: const Text('Reintentar')),
      ],
    ),
  );
}

class ReadLoading extends StatelessWidget {
  const ReadLoading({required this.label, super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.xxl),
    child: Center(child: CircularProgressIndicator(semanticsLabel: label)),
  );
}
