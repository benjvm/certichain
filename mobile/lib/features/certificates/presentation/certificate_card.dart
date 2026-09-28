import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_icons.dart';
import '../../../app/theme/app_sizes.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../domain/certificate_repository.dart';
import 'status_badge.dart';

String certificateDate(DateTime value) {
  final date = value.toLocal();
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class CertificateCard extends StatelessWidget {
  const CertificateCard({
    required this.certificate,
    required this.now,
    required this.onOpen,
    super.key,
  });
  final Certificate certificate;
  final DateTime now;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Semantics(
          button: true,
          hint: 'Abrir detalle del certificado',
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSizes.certificateCard,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    AppIcons.certificate,
                    color: AppColors.brandPrimary,
                    size: AppSizes.iconLarge,
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
                          certificate.institutionName ??
                              'Institución no disponible',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Wrap(
                          spacing: AppSpacing.md,
                          runSpacing: AppSpacing.sm,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            StatusBadge(
                              validity: certificate.validityAt(now),
                              compact: true,
                            ),
                            Text(
                              'Emitido: ${certificateDate(certificate.issuedAt)}',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        if (certificate.expiresAt case final expiry?) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Expira: ${certificateDate(expiry)}',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(
                    AppIcons.forward,
                    color: AppColors.textSecondary,
                    size: AppSizes.iconSmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
