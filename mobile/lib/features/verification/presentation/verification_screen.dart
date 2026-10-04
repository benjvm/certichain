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

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({
    required this.repository,
    this.initialCode,
    this.onHome,
    this.onCode,
    super.key,
  });
  final VerificationRepository repository;
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
  @override
  void initState() {
    super.initState();
    _controller = VerificationController(widget.repository);
    _text = TextEditingController(text: widget.initialCode ?? '');
    _controller.changeCode(_text.text);
    if (widget.initialCode != null) unawaited(_controller.submit());
  }

  @override
  void didUpdateWidget(VerificationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCode != widget.initialCode) {
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
                    _Result(result: result),
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
  const _Result({required this.result});
  final VerificationResult result;
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
                Text('Comprobado: ${_date(record.checkedAt)}'),
                const Text('Todas las fechas se muestran en UTC.'),
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
