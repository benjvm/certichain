import 'public_revocation_panel.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_sizes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_top_bar.dart';
import '../../../core/widgets/read_state.dart';
import '../domain/verification_repository.dart';
import 'verification_controller.dart';
import 'qr_scanner_panel.dart';
import 'public_query_cooldown.dart';
import '../domain/hash_comparison.dart';
import '../domain/verification_link.dart';
import '../domain/blockchain_verification.dart';
import 'blockchain_evidence_panel.dart';
import 'opening_check_panel.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({
    required this.repository,
    this.initialCode,
    this.cooldown,
    this.comparisonRepository,
    this.comparisonPicker,
    this.pdfHasher,
    this.verificationLink,
    this.scannerFactory,
    this.onHome,
    this.onCode,
    this.openingInput,
    super.key,
  });
  final VerificationRepository repository;
  final OpeningInput? openingInput;
  final PublicQueryCooldown? cooldown;
  final HashComparisonRepository? comparisonRepository;
  final ComparisonPdfPicker? comparisonPicker;
  final PdfHasher? pdfHasher;
  final VerificationLink? verificationLink;
  final ScannerSession Function()? scannerFactory;
  final String? initialCode;
  final VoidCallback? onHome;
  final ValueChanged<String?>? onCode;
  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  late final VerificationController _controller;
  late final TextEditingController _text;
  final _focus = FocusNode();
  bool _scanning = false;
  bool _openingCheck = false;
  @override
  void initState() {
    super.initState();
    _controller = VerificationController(
      widget.repository,
      comparisonRepository: widget.comparisonRepository,
      picker: widget.comparisonPicker,
      hasher: widget.pdfHasher,
      cooldown: widget.cooldown,
    );
    _text = TextEditingController(text: widget.initialCode ?? '');
    _controller.changeCode(_text.text);
    if (widget.initialCode != null) unawaited(_controller.submit());
  }

  @override
  void didUpdateWidget(VerificationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCode != widget.initialCode) {
      _scanning = false;
      _openingCheck = false;
      _text.text = widget.initialCode ?? '';
      _controller.changeCode(_text.text);
      if (widget.initialCode != null) unawaited(_controller.submit());
    }
  }

  void _submit() {
    if (!_controller.canSubmit) return;
    final code = normalizeCredentialCode(_text.text);
    if (code != null && widget.onCode != null && code != widget.initialCode) {
      widget.onCode!(code);
    } else {
      unawaited(_controller.submit());
    }
    if (code != null) {
      _text.text = code;
      _focus.unfocus();
    }
  }

  void _another() {
    _text.clear();
    _openingCheck = false;
    _controller.changeCode('');
    widget.onCode?.call(null);
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _comparisonMessage() => switch (_controller.comparisonPhase) {
    ComparisonPhase.idle =>
      'Selecciona la copia que quieres comparar (máximo 8 MiB).',
    ComparisonPhase.selecting => 'Seleccionando archivo…',
    ComparisonPhase.hashing => 'Calculando SHA-256 en tu dispositivo…',
    ComparisonPhase.querying => 'Comparando con el registro…',
    ComparisonPhase.cancelled => 'Comparación cancelada.',
    ComparisonPhase.done => switch (_controller.integrity) {
      FileIntegrity.match =>
        'El PDF coincide byte a byte con el documento registrado.',
      FileIntegrity.integrityMismatch =>
        'El PDF no coincide con el documento registrado.',
      _ => 'No hay un documento registrado elegible para comparar.',
    },
    ComparisonPhase.error => switch (_controller.localPdfFailure) {
      LocalPdfFailure.empty => 'El archivo está vacío.',
      LocalPdfFailure.tooLarge =>
        'El archivo supera el límite de 8 MiB (8.388.608 bytes).',
      LocalPdfFailure.unreadable =>
        'No pudimos leer el archivo. Selecciónalo de nuevo.',
      null => switch (_controller.comparisonFailure) {
        VerificationFailure.rateLimited =>
          'Temporalmente no se admiten más consultas.',
        VerificationFailure.timeout || VerificationFailure.network =>
          'No pudimos conectar. Reintenta manualmente.',
        VerificationFailure.unavailable =>
          'La comparación está temporalmente no disponible.',
        _ => 'No pudimos interpretar la comparación. Reintenta más tarde.',
      },
    },
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => Scaffold(
      appBar: AppTopBar(
        title: 'Verificar certificado',
        onBack: widget.onHome,
        textScale: MediaQuery.textScalerOf(context).scale(1),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSizes.contentWidth),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Consulta el registro de CertiChain. Esta comprobación no compara una copia del PDF ni acredita la identidad de quien lo presenta.',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (widget.scannerFactory != null &&
                      widget.verificationLink != null)
                    if (_scanning)
                      QrScannerPanel(
                        link: widget.verificationLink!,
                        createSession: widget.scannerFactory!,
                        onClose: () => setState(() => _scanning = false),
                        onCode: (code) {
                          setState(() => _scanning = false);
                          _text.text = code;
                          _controller.changeCode(code);
                          _submit();
                        },
                      )
                    else
                      AppButton(
                        label: 'Escanear QR',
                        style: AppButtonStyle.outline,
                        onPressed: () => setState(() => _scanning = true),
                      ),
                  TextField(
                    controller: _text,
                    focusNode: _focus,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.done,
                    onChanged: _controller.changeCode,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Código del certificado',
                      helperText: 'UUID de 36 caracteres con guiones.',
                      helperMaxLines: 3,
                      errorMaxLines: 3,
                      errorText:
                          _controller.failure ==
                              VerificationFailure.invalidInput
                          ? 'Introduce un código UUID válido.'
                          : null,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    label: 'Verificar',
                    isLoading: _controller.loading,
                    onPressed: _controller.canSubmit ? _submit : null,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (_controller.loading)
                    const ReadLoading(label: 'Consultando el registro'),
                  if (_controller.failure != null &&
                      _controller.failure != VerificationFailure.invalidInput)
                    Semantics(
                      liveRegion: true,
                      child: Text(switch (_controller.failure!) {
                        VerificationFailure.network ||
                        VerificationFailure.timeout =>
                          'No pudimos conectar. Reintenta manualmente.',
                        VerificationFailure.rateLimited =>
                          'Temporalmente no se admiten más consultas.',
                        VerificationFailure.unavailable =>
                          'La comprobación está temporalmente no disponible.',
                        _ => 'No pudimos interpretar la respuesta. Reintenta más tarde.',
                      }),
                    ),
                  if (_controller.waitSeconds > 0)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        'Espera ${_controller.waitSeconds} segundos para volver a consultar.',
                      ),
                    ),
                  if (_controller.result case final result?) ...[
                    if (_controller.resultIsPrevious)
                      Semantics(
                        liveRegion: true,
                        child: const Text(
                          'Resultado anterior. La nueva comparación aún no ha confirmado el estado del certificado. La fecha corresponde a la consulta anterior.',
                        ),
                      ),
                    _Result(
                      result: result,
                      previous: _controller.resultIsPrevious,
                    ),
                    if (result.revocation ?? _controller.previousRevocation
                        case final revocation?)
                      PublicRevocationPanel(
                        revocation: revocation,
                        previous:
                            _controller.resultIsPrevious ||
                            result.revocation == null,
                      )
                    else if (result.record != null)
                      const Text(
                        'Esta versión no incluye progreso ni evidencia de revocación. Su ausencia no demuestra que el certificado no esté revocado.',
                      ),
                    if (result.blockchain ?? _controller.previousBlockchain
                        case final evidence?)
                      BlockchainEvidencePanel(
                        evidence: evidence,
                        previous:
                            _controller.resultIsPrevious ||
                            result.blockchain == null,
                      ),
                    if ((result.record != null ||
                            _controller.comparisonPhase !=
                                ComparisonPhase.idle) &&
                        widget.comparisonRepository != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      const Text(
                        'Mi copia · Integridad del PDF',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Text(
                        'El archivo permanece en tu dispositivo. Solo se envían el código y su SHA-256. Volver a guardar un PDF puede cambiar sus bytes y producir una discrepancia. Una coincidencia no cambia el estado del certificado.',
                      ),
                      AppButton(
                        label: 'Comparar mi PDF',
                        style: AppButtonStyle.outline,
                        onPressed: _controller.canCompare
                            ? _controller.selectAndCompare
                            : null,
                      ),
                      Semantics(
                        liveRegion: true,
                        child: Text(_comparisonMessage()),
                      ),
                      if (_controller.comparisonPhase == ComparisonPhase.done &&
                          result.record != null)
                        Text(
                          'Comparación: ${result.record!.checkedAt.toUtc().toIso8601String()} · registro CertiChain (comparación candidata v1).',
                        ),
                      if (_controller.comparisonPhase ==
                              ComparisonPhase.error &&
                          _controller.comparisonFailure != null)
                        TextButton(
                          onPressed: _controller.canCompare
                              ? _controller.retryComparison
                              : null,
                          child: const Text('Reintentar comparación'),
                        ),
                      if ({
                        ComparisonPhase.selecting,
                        ComparisonPhase.hashing,
                        ComparisonPhase.querying,
                      }.contains(_controller.comparisonPhase))
                        TextButton(
                          onPressed: _controller.cancelComparison,
                          child: const Text('Cancelar comparación'),
                        ),
                    ],
                    if (result.record != null &&
                        widget.openingInput != null &&
                        widget.comparisonPicker != null &&
                        widget.pdfHasher != null) ...[
                      TextButton(
                        onPressed: _controller.loading
                            ? null
                            : () => setState(
                                () => _openingCheck = !_openingCheck,
                              ),
                        child: Text(
                          _openingCheck
                              ? 'Cerrar comprobación con apertura'
                              : 'Comprobar con apertura',
                        ),
                      ),
                      if (_openingCheck)
                        OpeningCheckPanel(
                          key: ValueKey((
                            result.record!.code,
                            result.blockchain,
                          )),
                          code: result.record!.code,
                          evidence: _controller.resultIsPrevious
                              ? null
                              : result.blockchain,
                          input: widget.openingInput!,
                          picker: widget.comparisonPicker!,
                          hasher: widget.pdfHasher!,
                        ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    AppButton(
                      label: 'Actualizar comprobación',
                      style: AppButtonStyle.outline,
                      onPressed: _controller.canSubmit ? _submit : null,
                    ),
                  ],
                  if (_controller.result != null || _controller.failure != null)
                    TextButton(
                      onPressed: _another,
                      child: const Text('Consultar otro código'),
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

class _Result extends StatelessWidget {
  const _Result({required this.result, this.previous = false});
  final VerificationResult result;
  final bool previous;
  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (result.status) {
      VerificationStatus.valid => (
        'Registro encontrado y vigente',
        Icons.check_circle_outline,
        AppColors.successText,
      ),
      VerificationStatus.revoked => (
        'Certificado revocado',
        Icons.cancel_outlined,
        AppColors.errorText,
      ),
      VerificationStatus.expired => (
        'Certificado caducado',
        Icons.schedule,
        AppColors.textSecondary,
      ),
      VerificationStatus.issuerUnavailable => (
        'Emisor sin aprobación vigente',
        Icons.info_outline,
        AppColors.textSecondary,
      ),
      VerificationStatus.notFound => (
        'No encontramos un registro verificable con este código',
        Icons.search_off,
        AppColors.textSecondary,
      ),
    };
    final record = result.record;
    return Semantics(
      liveRegion: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Registro CertiChain',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Icon(icon, color: color, size: 40),
              const SizedBox(height: AppSpacing.md),
              Text(
                label,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: color),
              ),
              if (record != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  record.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text('Emisor: ${record.issuer}'),
                Text('Emitido: ${_date(record.issuedAt)}'),
                Text(
                  record.expiresAt == null
                      ? 'Sin fecha de expiración'
                      : 'Expira: ${_date(record.expiresAt!)}',
                ),
                const SizedBox(height: AppSpacing.md),
                const Text('Código del certificado'),
                SelectableText(record.code),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '${previous ? 'Consulta anterior' : 'Comprobado'}: ${_date(record.checkedAt)}',
                ),
                const Text('Todas las fechas se muestran en UTC.'),
                const Text('Origen: registro CertiChain.'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _date(DateTime value) {
    final d = value.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}:${two(d.second)} UTC';
  }
}
