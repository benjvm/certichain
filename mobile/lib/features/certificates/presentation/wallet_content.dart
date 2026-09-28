import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_icons.dart';
import '../../../app/theme/app_sizes.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/widgets/read_state.dart';
import '../domain/certificate_repository.dart';
import 'certificate_card.dart';

class WalletContent extends StatelessWidget {
  const WalletContent({
    required this.future,
    required this.onRetry,
    required this.now,
    required this.onOpenCertificate,
    this.recent = false,
    this.onOpenWallet,
    this.homeActions,
    super.key,
  });
  final Future<CertificateWallet> future;
  final VoidCallback onRetry;
  final DateTime now;
  final bool recent;
  final VoidCallback? onOpenWallet;
  final ValueChanged<String> onOpenCertificate;
  final Widget? homeActions;
  @override
  Widget build(BuildContext context) => FutureBuilder<CertificateWallet>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ReadLoading(label: 'Cargando certificados'),
            const SizedBox(height: AppSpacing.section),
            ?homeActions,
          ],
        );
      }
      if (snapshot.hasError || !snapshot.hasData) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ReadError(
              message: 'No pudimos cargar tus certificados.',
              onRetry: onRetry,
            ),
            const SizedBox(height: AppSpacing.section),
            ?homeActions,
          ],
        );
      }
      final wallet = snapshot.requireData;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (recent) ...[
            Material(
              color: AppColors.brandPrimaryLight,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: InkWell(
                onTap: onOpenWallet,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  AppIcons.certificate,
                                  color: AppColors.brandPrimary,
                                  size: AppSizes.iconLarge,
                                ),
                                const SizedBox(width: AppSpacing.xl),
                                Text(
                                  '${wallet.total}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineLarge
                                      ?.copyWith(color: AppColors.brandPrimary),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              'Certificados en tu wallet',
                              style: AppTypography.label.copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        AppIcons.forward,
                        color: AppColors.brandPrimary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.section),
            ?homeActions,
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              children: [
                const Text(
                  'Certificados recientes',
                  style: AppTypography.sectionTitle,
                ),
                TextButton(
                  onPressed: onOpenWallet,
                  child: const Text('Ver todos'),
                ),
              ],
            ),
          ] else ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                selected: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.brandPrimary,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    'Todos',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.surface,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '${wallet.total} certificados · ordenados por fecha de emisión',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            if (wallet.total > wallet.certificates.length)
              const Text('Se muestran los 50 más recientes.'),
            const SizedBox(height: AppSpacing.xxl),
          ],
          if (wallet.certificates.isEmpty)
            const ReadEmpty(
              title: 'Aún no tienes certificados',
              message: 'Cuando una institución te emita un certificado, aparecerá aquí.',
            )
          else
            ...wallet.certificates
                .take(recent ? 3 : CertificateRepository.walletLimit)
                .map(
                  (certificate) => CertificateCard(
                    certificate: certificate,
                    now: now,
                    onOpen: () => onOpenCertificate(certificate.id),
                  ),
                ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'El estado indica vigencia y revocación. No acredita verificación en blockchain.',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (!recent) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'PDF y QR: no disponibles todavía.',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      );
    },
  );
}
