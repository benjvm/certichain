import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../domain/certificate_repository.dart';

String certificateDate(DateTime value) {
  final date = value.toLocal();
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class CertificateCard extends StatelessWidget {
  const CertificateCard({
    required this.certificate,
    required this.now,
    super.key,
  });
  final Certificate certificate;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final (label, icon, background) = switch (certificate.validityAt(now)) {
      CertificateValidity.valid => (
        'Válido',
        Icons.check_circle_outline_rounded,
        AppColors.successLight,
      ),
      CertificateValidity.revoked => (
        'Revocado',
        Icons.block_rounded,
        AppColors.errorLight,
      ),
      CertificateValidity.expired => (
        'Expirado',
        Icons.schedule_rounded,
        AppColors.background,
      ),
    };
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              backgroundColor: AppColors.brandPrimaryLight,
              child: Icon(
                Icons.workspace_premium_outlined,
                color: AppColors.brandPrimary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    certificate.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    certificate.institutionName ?? 'Institución no disponible',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(
                        avatar: Icon(icon, size: 18),
                        label: Text(label),
                        backgroundColor: background,
                        side: BorderSide.none,
                      ),
                      Text('Emitido: ${certificateDate(certificate.issuedAt)}'),
                    ],
                  ),
                  if (certificate.expiresAt case final expiry?)
                    Text('Expira: ${certificateDate(expiry)}'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
