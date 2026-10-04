import 'package:flutter/material.dart';

import '../../../core/widgets/app_button.dart';
import '../domain/certificate_document_repository.dart';

class DocumentAction extends StatefulWidget {
  const DocumentAction({
    required this.userId,
    required this.certificateId,
    required this.repository,
    required this.onSessionExpired,
    super.key,
  });
  final String userId;
  final String certificateId;
  final CertificateDocumentRepository repository;
  final VoidCallback onSessionExpired;
  @override
  State<DocumentAction> createState() => _DocumentActionState();
}

class _DocumentActionState extends State<DocumentAction>
    with WidgetsBindingObserver {
  bool? _available;
  bool _busy = false;
  String? _message;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  Future<void> _check() async {
    final generation = ++_generation;
    setState(() {
      _available = null;
      _message = null;
    });
    try {
      final available = await widget.repository.isAvailable(
        widget.userId,
        widget.certificateId,
      );
      if (mounted && generation == _generation) {
        setState(() => _available = available);
      }
    } catch (error) {
      if (mounted && generation == _generation) _error(error);
    }
  }

  void _error(Object error) {
    if (error is DocumentException && error.code == 'unauthenticated') {
      widget.onSessionExpired();
      return;
    }
    setState(
      () => _message = error is DocumentException
          ? error.message
          : 'No pudimos comprobar el PDF. Reintenta.',
    );
  }

  Future<void> _download() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final saved = await widget.repository.download(
        widget.userId,
        widget.certificateId,
      );
      if (mounted) {
        setState(
          () => _message = saved
              ? 'Descarga enviada. Revisa tus archivos.'
              : 'Descarga cancelada.',
        );
      }
    } catch (error) {
      if (mounted) _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void didUpdateWidget(DocumentAction old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId ||
        old.certificateId != widget.certificateId ||
        old.repository != widget.repository) {
      _check();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_available == null && _message == null)
        const Text('Comprobando acceso al PDF…'),
      if (_available == false)
        const Text('Este certificado no tiene un PDF disponible o accesible.'),
      if (_available == true)
        AppButton(
          label: 'Descargar PDF',
          onPressed: _download,
          isLoading: _busy,
        ),
      if (_message != null) Semantics(liveRegion: true, child: Text(_message!)),
      if (!_busy && (_available != true || _message != null))
        TextButton(
          onPressed: _check,
          child: const Text('Comprobar PDF de nuevo'),
        ),
    ],
  );
}
