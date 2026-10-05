import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_sizes.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_top_bar.dart';
import '../../institutions/domain/institution_repository.dart';
import '../domain/issuance_repository.dart';
import 'issuance_controller.dart';

class IssuanceScreen extends StatefulWidget {
  const IssuanceScreen({
    required this.userId,
    required this.institution,
    required this.institutions,
    required this.repository,
    required this.picker,
    required this.store,
    required this.onSessionExpired,
    this.sessionChanges,
    this.clock,
    this.onConfirmed,
    super.key,
  });
  final String userId;
  final InstitutionMembership institution;
  final InstitutionRepository institutions;
  final IssuanceRepository repository;
  final PdfPicker picker;
  final PendingAttemptStore store;
  final VoidCallback onSessionExpired;
  final Listenable? sessionChanges;
  final DateTime Function()? clock;
  final VoidCallback? onConfirmed;
  @override
  State<IssuanceScreen> createState() => _IssuanceScreenState();
}

class _IssuanceScreenState extends State<IssuanceScreen>
    with WidgetsBindingObserver {
  late final IssuanceController _controller;
  final _form = GlobalKey<FormState>();
  final _holder = TextEditingController(),
      _title = TextEditingController(),
      _description = TextEditingController();
  IssuanceData? _data;
  SelectedPdf? _pdf;
  DateTime? _expires;
  InstitutionMembership? _membership;
  int _step = 0, _generation = 0;
  bool _checking = true, _picking = false;
  String? _localError;
  Timer? _timer;
  bool _announced = false;
  @override
  void initState() {
    super.initState();
    _controller = IssuanceController(
      userId: widget.userId,
      institutionId: widget.institution.id,
      repository: widget.repository,
      store: widget.store,
      clock: widget.clock,
    )..addListener(_changed);
    unawaited(_controller.restore());
    WidgetsBinding.instance.addObserver(this);
    widget.sessionChanges?.addListener(_refresh);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_controller.retryAt != null && mounted) setState(() {});
      if (timer.tick % 30 == 0) _refresh();
    });
  }

  void _changed() {
    if (!mounted) return;
    if (_controller.failure?.code == 'unauthenticated') {
      widget.onSessionExpired();
      return;
    }
    if (_controller.certificateId != null && !_announced) {
      _announced = true;
      widget.onConfirmed?.call();
    }
    if (_controller.failure?.code == 'forbidden') _refresh();
    setState(() {});
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    if (mounted) setState(() => _checking = true);
    try {
      final members = await widget.institutions.readMemberships(widget.userId);
      if (!mounted || generation != _generation) return;
      final matches = members.where((m) => m.id == widget.institution.id);
      setState(() {
        _membership = matches.isEmpty ? null : matches.first;
        _checking = false;
        _localError = null;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _checking = false;
          _membership = null;
          _localError =
              'No pudimos comprobar tus permisos. Actualiza antes de emitir.';
        });
      }
    }
  }

  Future<void> _pick() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _localError = null;
    });
    try {
      final pdf = await widget.picker.pick();
      if (mounted && pdf != null) setState(() => _pdf = pdf);
    } catch (error) {
      if (mounted) {
        setState(
          () => _localError = error is IssuanceException
              ? error.message
              : 'No pudimos leer el archivo. Selecciónalo de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _date() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _expires ?? now.add(const Duration(days: 1)),
      firstDate: _controller.pending == null
          ? DateTime(now.year, now.month, now.day + 1)
          : DateTime(2000),
      lastDate: DateTime(now.year + 10, now.month, now.day),
    );
    if (mounted && date != null) {
      setState(() => _expires = DateTime.utc(date.year, date.month, date.day));
    }
  }

  void _next() {
    if (_step == 0) {
      if (!_form.currentState!.validate()) return;
      try {
        _data = IssuanceData(
          holderId: _holder.text,
          title: _title.text,
          description: _description.text,
          expiresAt: _expires,
          reconstructing: _controller.pending != null,
        );
      } catch (error) {
        setState(() => _localError = (error as IssuanceException).message);
        return;
      }
    }
    if (_step == 1 && _pdf == null) {
      setState(() => _localError = 'Selecciona un PDF antes de confirmar.');
      return;
    }
    setState(() {
      _step++;
      _localError = null;
    });
  }

  Future<void> _submit() async {
    if (_controller.busy || _checking || !_controller.ready) return;
    await _refresh();
    if (!mounted || _membership?.canIssue != true) return;
    await _controller.submit(_data!, _pdf!);
  }

  Future<void> _newAttempt() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Iniciar una emisión nueva'),
        content: const Text(
          'Una clave nueva puede crear un duplicado si la operación anterior se completó. Revisa primero Certificados emitidos y, ante conflicto o intento fallido, consulta con administración. Esta acción abandona el recibo anterior y no cancela el backend.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Conservar intento'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Iniciar emisión nueva'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      try {
        await _controller.startNewDeliberately();
        if (mounted) setState(() => _step = 0);
      } catch (_) {
        if (mounted) {
          setState(
            () => _localError = 'No pudimos retirar el recibo. Reintenta.',
          );
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    widget.picker.cancel();
    _timer?.cancel();
    _generation++;
    widget.sessionChanges?.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _holder.dispose();
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locked = _controller.request != null;
    final allowed = !_checking && _membership?.canIssue == true;
    return PopScope(
      canPop: !_controller.busy,
      child: Scaffold(
        appBar: AppTopBar(
          title: 'Emitir certificado',
          onBack: _controller.busy ? null : () => Navigator.pop(context, false),
          onRefresh: _refresh,
          textScale: MediaQuery.textScalerOf(context).scale(1),
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSizes.contentWidth,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_controller.certificateId case final id?) ...[
                      const Icon(Icons.check_circle_outline, size: 48),
                      const Text(
                        'Certificado emitido',
                        textAlign: TextAlign.center,
                      ),
                      SelectableText(id),
                      const Text(
                        'El certificado ya está disponible en la wallet de su titular.',
                      ),
                      AppButton(
                        label: 'Ir a Certificados emitidos',
                        onPressed: () => Navigator.pop(context, true),
                      ),
                    ] else ...[
                      Text(
                        _membership?.name ?? widget.institution.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        _membership == null
                            ? 'Membresía no disponible'
                            : '${_membership!.role.name} · ${_membership!.statusLabel}',
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (_checking)
                        const Text('Comprobando membresía actual…'),
                      if (!allowed && !_checking)
                        Text(
                          _localError ?? _membership?.blockReason ?? 'Ya no perteneces a esta institución. No puedes emitir.',
                        ),
                      if (_controller.pending != null && !locked) ...[
                        const Text(
                          'Hay un intento pendiente de esta cuenta e institución. Introduce exactamente sus datos y selecciona otra vez el PDF original. Solo se reutilizará su clave si la huella coincide. El recibo se conserva 7 días; después revisa el listado antes de emitir para evitar duplicados.',
                        ),
                        SelectableText('Clave: ${_controller.pending!.key}'),
                      ],
                      if (allowed) ...[
                        Wrap(
                          spacing: AppSpacing.md,
                          runSpacing: AppSpacing.sm,
                          children: [
                            for (final (index, label) in [
                              (0, 'Datos'),
                              (1, 'Documento'),
                              (2, 'Confirmar'),
                            ])
                              Semantics(
                                selected: _step == index,
                                child: Chip(
                                  label: Text('${index + 1} · $label'),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        if (_step == 0)
                          Form(
                            key: _form,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextFormField(
                                  key: const Key('holder-id'),
                                  controller: _holder,
                                  decoration: const InputDecoration(
                                    labelText: 'ID del titular',
                                    errorMaxLines: 4,
                                    helperText: 'UUID compartido voluntariamente por el estudiante desde Mi perfil.',
                                    helperMaxLines: 4,
                                  ),
                                  validator: (value) =>
                                      isUuid((value ?? '').trim()) ? null : 'Introduce un ID de titular UUID válido.',
                                ),
                                TextButton(
                                  onPressed: () async {
                                    try {
                                      final value = await Clipboard.getData(
                                        Clipboard.kTextPlain,
                                      );
                                      if (mounted && value?.text != null) {
                                        _holder.text = value!.text!.trim();
                                      }
                                    } catch (_) {
                                      if (mounted) {
                                        setState(
                                          () => _localError = 'No pudimos pegar. Introduce el ID manualmente.',
                                        );
                                      }
                                    }
                                  },
                                  child: const Text('Pegar ID del titular'),
                                ),
                                TextFormField(
                                  key: const Key('issuance-title'),
                                  controller: _title,
                                  decoration: const InputDecoration(
                                    labelText: 'Título',
                                    helperText: '1–200 caracteres',
                                  ),
                                  validator: (value) =>
                                      IssuanceData.titleError(value ?? ''),
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                TextFormField(
                                  key: const Key('issuance-description'),
                                  controller: _description,
                                  maxLines: 3,
                                  decoration: const InputDecoration(
                                    labelText: 'Descripción (opcional)',
                                    helperText: 'Hasta 4000 caracteres, sin saltos de línea ni controles.',
                                    helperMaxLines: 3,
                                  ),
                                  validator: IssuanceData.descriptionError,
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                Text(
                                  _expires == null
                                      ? 'Sin fecha de expiración'
                                      : 'Expiración (00:00 UTC): ${_expires!.toIso8601String().substring(0, 10)}',
                                ),
                                TextButton(
                                  onPressed: _date,
                                  child: const Text(
                                    'Elegir expiración (opcional)',
                                  ),
                                ),
                                if (_expires != null)
                                  TextButton(
                                    onPressed: () =>
                                        setState(() => _expires = null),
                                    child: const Text('Quitar expiración'),
                                  ),
                              ],
                            ),
                          ),
                        if (_step == 1) ...[
                          const Text(
                            'Un PDF .pdf, máximo 8 MiB. El servidor valida el contenido real y la compatibilidad del documento.',
                          ),
                          if (_pdf != null)
                            Text('${_pdf!.name}\n${_pdf!.bytes.length} bytes'),
                          AppButton(
                            label: _pdf == null
                                ? 'Seleccionar PDF'
                                : 'Reemplazar PDF',
                            onPressed: _pick,
                            isLoading: _picking,
                            style: AppButtonStyle.outline,
                          ),
                        ],
                        if (_step == 2) ...[
                          const Text('Revisa antes de emitir'),
                          _summary('Institución', _membership!.name),
                          _summary('ID del titular', _data!.holderId),
                          _summary('Título', _data!.title),
                          _summary(
                            'Descripción',
                            _data!.description ?? 'Sin descripción',
                          ),
                          _summary(
                            'Expiración (UTC)',
                            _data!.expiresAt ?? 'Sin expiración',
                          ),
                          _summary(
                            'PDF',
                            '${_pdf!.name} · ${_pdf!.bytes.length} bytes',
                          ),
                          if (_controller.busy)
                            const Text(
                              'Esperando la confirmación del servidor. No cierres la pantalla. La petición no comunica un porcentaje de progreso.',
                            ),
                          if (_controller.failure case final failure?)
                            Semantics(
                              liveRegion: true,
                              child: Text(failure.message),
                            ),
                          if (_controller.retryAt != null &&
                              !_controller.canRetry &&
                              _controller.failure?.recoverable == true)
                            Text(
                              'Podrás reintentar en ${_controller.retryAt!.difference(_controller.now).inSeconds.clamp(0, 86400)} segundos.',
                            ),
                          AppButton(
                            label: locked && !_controller.busy
                                ? 'Reintentar'
                                : 'Emitir certificado',
                            onPressed:
                                !_controller.ready ||
                                    _controller.failure != null &&
                                        locked &&
                                        !_controller.canRetry
                                ? null
                                : _submit,
                            isLoading: _controller.busy,
                          ),
                        ],
                        if (_step < 2)
                          AppButton(label: 'Siguiente', onPressed: _next),
                        if (_step > 0 && !locked)
                          TextButton(
                            onPressed: () => setState(() => _step--),
                            child: const Text('Anterior'),
                          ),
                      ],
                      if (_localError != null && allowed)
                        Semantics(liveRegion: true, child: Text(_localError!)),
                      if ((_controller.pending != null || locked) &&
                          !_controller.busy)
                        TextButton(
                          onPressed: _newAttempt,
                          child: const Text(
                            'Revisé la operación · Iniciar una emisión nueva',
                          ),
                        ),
                      if (!_controller.ready)
                        TextButton(
                          onPressed: _controller.restore,
                          child: const Text('Cargar recibo de recuperación'),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _summary(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        SelectableText(value),
      ],
    ),
  );
}
