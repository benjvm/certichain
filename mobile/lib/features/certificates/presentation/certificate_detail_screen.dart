import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_icons.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_sizes.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_top_bar.dart';
import '../../../core/widgets/read_state.dart';
import '../domain/certificate_repository.dart';
import 'certificate_card.dart';
import 'status_badge.dart';
import '../domain/certificate_document_repository.dart';
import 'document_action.dart';

enum CertificateDetailSection { details, blockchain, history }

class CertificateDetailScreen extends StatefulWidget {
  const CertificateDetailScreen({
    required this.userId,
    required this.certificateId,
    required this.repository,
    this.documents,
    this.onSessionExpired,
    super.key,
  });
  final String userId;
  final String certificateId;
  final CertificateRepository repository;
  final CertificateDocumentRepository? documents;
  final VoidCallback? onSessionExpired;

  @override
  State<CertificateDetailScreen> createState() =>
      _CertificateDetailScreenState();
}

class _CertificateDetailScreenState extends State<CertificateDetailScreen>
    with WidgetsBindingObserver {
  late Future<Certificate?> _certificate;
  CertificateDetailSection _section = CertificateDetailSection.details;
  Timer? _expiry;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _read();
  }

  void _read() {
    _expiry?.cancel();
    final request = ++_request;
    _certificate = widget.repository.readCertificate(
      widget.userId,
      widget.certificateId,
    );
    unawaited(
      _certificate.then<void>((certificate) {
        if (!mounted || request != _request) return;
        final expiry = certificate?.expiresAt;
        final now = DateTime.now();
        if (certificate?.status == CertificateStatus.active &&
            expiry != null &&
            expiry.isAfter(now)) {
          _expiry = Timer(expiry.difference(now), () {
            if (mounted && request == _request) setState(() {});
          });
        }
      }, onError: (Object _, StackTrace _) {}),
    );
  }

  void _refresh() => setState(_read);

  @override
  void didUpdateWidget(CertificateDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.certificateId != widget.certificateId ||
        oldWidget.repository != widget.repository) {
      _section = CertificateDetailSection.details;
      _read();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _expiry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppTopBar(
      title: 'Detalle del certificado',
      onBack: () => Navigator.of(context).pop(),
      onRefresh: _refresh,
      textScale: MediaQuery.textScalerOf(context).scale(1),
    ),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.contentWidth),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
            child: FutureBuilder<Certificate?>(
              future: _certificate,
              builder: (context, snapshot) {
                // FutureBuilder can retain old data while waiting: never display it.
                if (snapshot.connectionState != ConnectionState.done) {
                  return const ReadLoading(label: 'Cargando certificado');
                }
                if (snapshot.hasError) {
                  return ReadError(
                    message: 'No pudimos cargar este certificado.',
                    onRetry: _refresh,
                  );
                }
                final certificate = snapshot.data;
                if (certificate == null) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ReadEmpty(
                        title: 'Certificado no disponible',
                        message:
                            'No existe o no tienes acceso a este certificado.',
                      ),
                      TextButton(
                        onPressed: _refresh,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  );
                }
                return _content(context, certificate);
              },
            ),
          ),
        ),
      ),
    ),
  );

  Widget _content(BuildContext context, Certificate certificate) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.documents == null)
        const CertificatePreview()
      else
        DocumentAction(
          key: ValueKey((widget.userId, certificate.id, _request)),
          userId: widget.userId,
          certificateId: certificate.id,
          repository: widget.documents!,
          onSessionExpired: widget.onSessionExpired ?? () {},
        ),
      const SizedBox(height: AppSpacing.xxl),
      Text(
        certificate.title,
        style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(color: AppColors.inkBlue),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        certificate.institutionName ?? 'Institución no disponible',
        style: AppTypography.label.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w400,
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      Align(
        alignment: Alignment.centerLeft,
        child: StatusBadge(validity: certificate.validityAt(DateTime.now())),
      ),
      const SizedBox(height: AppSpacing.md),
      _date(
        AppIcons.calendar,
        'Emitido: ${certificateDate(certificate.issuedAt)}',
      ),
      const SizedBox(height: AppSpacing.sm),
      _date(
        AppIcons.time,
        certificate.expiresAt == null
            ? 'Sin fecha de expiración'
            : 'Expira: ${certificateDate(certificate.expiresAt!)}',
      ),
      const SizedBox(height: AppSpacing.lg),
      Text(
        'El estado indica vigencia y revocación. No acredita verificación en blockchain.',
        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
      ),
      const SizedBox(height: AppSpacing.xxl),
      const Text(
        'QR y verificación pública: no disponibles todavía.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: AppSpacing.lg),
      const AppButton(
        label: 'Compartir certificado · No disponible',
        onPressed: null,
        style: AppButtonStyle.outline,
      ),
      const SizedBox(height: AppSpacing.xxl),
      DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          children: [
            for (final section in CertificateDetailSection.values)
              Semantics(
                selected: _section == section,
                child: TextButton(
                  onPressed: () => setState(() => _section = section),
                  style: TextButton.styleFrom(
                    foregroundColor: _section == section
                        ? AppColors.brandPrimaryDark
                        : AppColors.textSecondary,
                  ),
                  child: Text(switch (section) {
                    CertificateDetailSection.details => 'Detalles',
                    CertificateDetailSection.blockchain => 'Blockchain',
                    CertificateDetailSection.history => 'Historial',
                  }),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      switch (_section) {
        CertificateDetailSection.details => Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ID del certificado', style: AppTypography.label),
                const SizedBox(height: AppSpacing.sm),
                SelectableText(certificate.id),
              ],
            ),
          ),
        ),
        CertificateDetailSection.blockchain => const ReadEmpty(
          title: 'Sin datos de blockchain',
          message: 'No hay información de registro o verificación blockchain disponible.',
          icon: AppIcons.security,
        ),
        CertificateDetailSection.history => const ReadEmpty(
          title: 'Historial no disponible',
          message: 'El backend todavía no proporciona un historial de este certificado.',
          icon: AppIcons.time,
        ),
      },
    ],
  );

  Widget _date(IconData icon, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: AppSizes.iconSmall, color: AppColors.textSecondary),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Text(
          text,
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
      ),
    ],
  );
}

/// The design slot is preserved without pretending to render the private PDF.
class CertificatePreview extends StatelessWidget {
  const CertificatePreview({super.key});
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: AppSizes.previewWidth,
        minHeight: AppSizes.previewHeight,
      ),
      child: Card(
        color: AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xs),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                AppIcons.document,
                color: AppColors.brandPrimary,
                size: AppSizes.iconLarge,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Vista previa no disponible',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'El PDF todavía no está disponible.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
