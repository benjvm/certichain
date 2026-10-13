import 'package:flutter/material.dart';

import '../../../core/widgets/app_button.dart';
import '../domain/blockchain_verification.dart';
import '../domain/hash_comparison.dart';
import 'opening_check_controller.dart';

class OpeningCheckPanel extends StatefulWidget {
  const OpeningCheckPanel({
    required this.code,
    required this.evidence,
    required this.input,
    required this.picker,
    required this.hasher,
    super.key,
  });
  final String code;
  final BlockchainEvidence? evidence;
  final OpeningInput input;
  final ComparisonPdfPicker picker;
  final PdfHasher hasher;
  @override
  State<OpeningCheckPanel> createState() => _OpeningCheckPanelState();
}

class _OpeningCheckPanelState extends State<OpeningCheckPanel> {
  late final OpeningCheckController _controller;
  final _json = TextEditingController();
  @override
  void initState() {
    super.initState();
    _controller = OpeningCheckController(
      widget.input,
      widget.picker,
      widget.hasher,
    );
  }

  @override
  void didUpdateWidget(OpeningCheckPanel old) {
    super.didUpdateWidget(old);
    if (old.code != widget.code || old.evidence != widget.evidence) {
      _controller.reset();
      _json.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _json.clear();
    _json.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Validez de la apertura',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const Text(
          'El PDF y la apertura permanecen en tu dispositivo. Se recalculan SHA-256 y el compromiso localmente. La evidencia EVM procede del backend RPC o del receipt persistido declarado. Una coincidencia no acredita identidad ni cambia revocación o caducidad.',
        ),
        TextField(
          controller: _json,
          maxLength: 2048,
          maxLines: 4,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'JSON de apertura (máximo 2 KiB)',
          ),
          onChanged: (_) => _controller.reset(),
        ),
        TextButton(
          onPressed: _controller.busy
              ? null
              : () async {
                  await _controller.import();
                  if (mounted && _controller.imported != null) {
                    _json.text = _controller.imported!;
                  }
                },
          child: const Text('Importar apertura JSON'),
        ),
        AppButton(
          label: 'Seleccionar PDF y comprobar apertura',
          isLoading: _controller.busy,
          onPressed: _controller.busy
              ? null
              : () async {
                  final source = _json.text;
                  _json.clear();
                  await _controller.check(source, widget.code, widget.evidence);
                },
        ),
        if (_controller.busy)
          TextButton(
            onPressed: () {
              _controller.reset();
              _json.clear();
            },
            child: const Text('Cancelar comprobación'),
          ),
        if (_controller.pdfFailure case final failure?)
          Text(switch (failure) {
            LocalPdfFailure.empty => 'El PDF está vacío.',
            LocalPdfFailure.tooLarge => 'El PDF supera 8 MiB.',
            LocalPdfFailure.unreadable => 'No se pudo leer el PDF.',
          }),
        if (_controller.result case final r?)
          Semantics(
            liveRegion: true,
            child: Text(switch (r.validity) {
              OpeningValidity.match =>
                'Apertura válida: el PDF corresponde al compromiso comprobado.',
              OpeningValidity.pdfMismatch =>
                'Mi copia: PDF no coincidente con la apertura.',
              OpeningValidity.invalidOpening =>
                'Apertura inválida o de otro certificado/contrato.',
              OpeningValidity.evidenceUnavailable => 'La copia coincide con la apertura, pero la evidencia actual no es comprobable.',
            }),
          ),
        if (_controller.result?.evidenceCheckedAt case final date?)
          Text(
            'Evidencia utilizada: ${date.toUtc().toIso8601String()} · backend RPC. Cálculo documental local.',
          ),
      ],
    ),
  );
}
