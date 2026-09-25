import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../core/widgets/read_state.dart';
import '../domain/certificate_repository.dart';
import 'certificate_card.dart';

class WalletContent extends StatelessWidget {
  const WalletContent({
    required this.future,
    required this.onRetry,
    required this.now,
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
            ?homeActions,
          ],
        );
      }
      final wallet = snapshot.requireData;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (recent) ...[
            Card(
              color: AppColors.brandPrimaryLight,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${wallet.total}',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const Text('Certificados en tu wallet'),
                    TextButton(
                      onPressed: onOpenWallet,
                      child: const Text('Ver todos'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ?homeActions,
            Text(
              'Certificados recientes',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ] else ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: Chip(label: Text('Todos')),
            ),
            Text(
              '${wallet.total} certificados · ordenados por fecha de emisión',
            ),
            if (wallet.total > wallet.certificates.length)
              const Text('Se muestran los 50 más recientes.'),
            const SizedBox(height: AppSpacing.md),
          ],
          if (wallet.certificates.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: Column(
                children: [
                  Icon(Icons.folder_open_rounded, size: AppSpacing.large),
                  SizedBox(height: AppSpacing.md),
                  Text('Aún no tienes certificados'),
                  Text(
                    'Cuando una institución te emita un certificado, aparecerá aquí.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            ...wallet.certificates
                .take(recent ? 3 : CertificateRepository.walletLimit)
                .map(
                  (certificate) =>
                      CertificateCard(certificate: certificate, now: now),
                ),
          const Text(
            'El estado indica vigencia y revocación. No acredita verificación en blockchain.',
          ),
          if (!recent) const Text('Detalle, PDF y QR: no disponibles todavía.'),
        ],
      );
    },
  );
}
