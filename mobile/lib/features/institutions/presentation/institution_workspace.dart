import '../../revocation/domain/revocation_repository.dart';
import '../../revocation/presentation/revocation_panel.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/app_sizes.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/router/app_router.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_top_bar.dart';
import '../../../core/widgets/read_state.dart';
import '../../certificates/domain/certificate_repository.dart';
import '../../certificates/domain/certificate_document_repository.dart';
import '../../certificates/presentation/certificate_card.dart';
import '../../certificates/presentation/status_badge.dart';
import '../../certificates/presentation/document_action.dart';
import '../../issuance/domain/issuance_repository.dart';
import '../../issuance/presentation/issuance_screen.dart';
import '../domain/institution_repository.dart';
import '../../issuance/domain/anchoring_repository.dart';
import '../../issuance/presentation/anchoring_panel.dart';
import '../../certificates/presentation/opening_action.dart';

class InstitutionWorkspace extends StatefulWidget {
  const InstitutionWorkspace({
    required this.userId,
    required this.repository,
    required this.issuance,
    required this.picker,
    required this.store,
    required this.onSessionExpired,
    this.documents,
    this.sessionChanges,
    this.anchoring,
    this.revocations,
    this.revocationKeys,
    this.anchorStore,
    this.openings,
    this.openingTransfer,
    super.key,
  });
  final String userId;
  final RevocationRepository? revocations;
  final RevocationKeyStore? revocationKeys;
  final AnchoringRepository? anchoring;
  final AnchorReceiptStore? anchorStore;
  final OpeningRepository? openings;
  final OpeningTransfer? openingTransfer;
  final InstitutionRepository repository;
  final IssuanceRepository issuance;
  final PdfPicker picker;
  final PendingAttemptStore store;
  final CertificateDocumentRepository? documents;
  final VoidCallback onSessionExpired;
  final Listenable? sessionChanges;
  @override
  State<InstitutionWorkspace> createState() => _InstitutionWorkspaceState();
}

class _InstitutionWorkspaceState extends State<InstitutionWorkspace>
    with WidgetsBindingObserver {
  late Future<List<InstitutionMembership>> _members;
  Future<CertificateWallet>? _issued;
  String? _active;
  String? _documentId;
  String? _anchorId;
  String? _revocationId;
  String? _openingId;
  bool _opening = false;
  final _revoked = <String>{};
  CertificateValidity _validity(Certificate c) => _revoked.contains(c.id)
      ? CertificateValidity.revoked
      : c.validityAt(DateTime.now());
  int _generation = 0;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.sessionChanges?.addListener(_refresh);
    _read();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  void _read() {
    final generation = ++_generation;
    _issued = null;
    _revoked.clear();
    _documentId = null;
    _anchorId = null;
    _revocationId = null;
    _openingId = null;
    _members = widget.repository.readMemberships(widget.userId);
    unawaited(
      _members.then((members) {
        if (!mounted || generation != _generation) return;
        if (!members.any((m) => m.id == _active)) {
          _active = members.firstOrNull?.id;
        }
        if (_active != null) setState(_readIssued);
      }, onError: (Object _, StackTrace _) {}),
    );
  }

  void _readIssued() {
    _issued = widget.repository.readIssued(_active!);
    unawaited(
      _issued!.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  void _refresh() => setState(_read);
  Future<void> _issue(InstitutionMembership member) async {
    if (_opening) return;
    _opening = true;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        settings: RouteSettings(
          name: AppRouter.issuanceRoute,
          arguments: member.id,
        ),
        builder: (_) => IssuanceScreen(
          userId: widget.userId,
          institution: member,
          institutions: widget.repository,
          repository: widget.issuance,
          picker: widget.picker,
          store: widget.store,
          onSessionExpired: widget.onSessionExpired,
          sessionChanges: widget.sessionChanges,
          onConfirmed: _refresh,
        ),
      ),
    );
    _opening = false;
    if (mounted) _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    widget.sessionChanges?.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppTopBar(
      title: 'Certificados emitidos',
      onBack: () => Navigator.pop(context),
      onRefresh: _refresh,
      textScale: MediaQuery.textScalerOf(context).scale(1),
    ),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.contentWidth),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: FutureBuilder<List<InstitutionMembership>>(
              future: _members,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const ReadLoading(label: 'Comprobando membresías');
                }
                if (snapshot.hasError) {
                  return ReadError(
                    message: 'No pudimos cargar tus instituciones.',
                    onRetry: _refresh,
                  );
                }
                final members = snapshot.data!;
                if (members.isEmpty) {
                  return const ReadEmpty(
                    title: 'Sin membresías institucionales',
                    message: 'Tu cuenta mantiene su wallet de titular. Una preferencia de registro no concede permisos institucionales.',
                  );
                }
                final selected = members
                    .where((m) => m.id == _active)
                    .firstOrNull;
                if (selected == null) {
                  return const ReadLoading(label: 'Seleccionando institución');
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey(('institution-selector', _active)),
                      initialValue: _active,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Institución activa',
                      ),
                      items: members
                          .map(
                            (m) => DropdownMenuItem(
                              value: m.id,
                              child: Text(
                                m.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (id) {
                        if (id != null) {
                          setState(() {
                            _active = id;
                            _documentId = null;
                            _anchorId = null;
                            _revocationId = null;
                            _openingId = null;
                            _readIssued();
                          });
                        }
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(selected.name),
                    Text('${selected.role.name} · ${selected.statusLabel}'),
                    if (!selected.canIssue) Text(selected.blockReason),
                    const SizedBox(height: AppSpacing.lg),
                    AppButton(
                      label: 'Emitir certificado',
                      onPressed: selected.canIssue
                          ? () => _issue(selected)
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    if (_issued != null)
                      FutureBuilder<CertificateWallet>(
                        key: ValueKey(_active),
                        future: _issued,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const ReadLoading(
                              label: 'Cargando certificados emitidos',
                            );
                          }
                          if (snapshot.hasError) {
                            return ReadError(
                              message: 'No pudimos cargar los certificados emitidos.',
                              onRetry: () => setState(_readIssued),
                            );
                          }
                          final wallet = snapshot.data!;
                          if (wallet.total == 0) {
                            return const ReadEmpty(
                              title: 'Todavía no hay certificados emitidos',
                              message: 'Las emisiones confirmadas de esta institución aparecerán aquí.',
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Últimos ${wallet.certificates.length} de ${wallet.total} · Límite 50',
                              ),
                              for (final c in wallet.certificates)
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(
                                      AppSpacing.lg,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          c.title,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall,
                                        ),
                                        Text(
                                          'Emitido: ${certificateDate(c.issuedAt)}',
                                        ),
                                        Text(
                                          'Referencia: ${c.id.substring(0, 8)}',
                                        ),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: StatusBadge(
                                            validity: _validity(c),
                                          ),
                                        ),
                                        if (widget.revocations != null &&
                                            widget.revocationKeys != null &&
                                            selected.canRevoke)
                                          if (_revocationId != c.id)
                                            TextButton(
                                              onPressed: () => setState(
                                                () => _revocationId = c.id,
                                              ),
                                              child: const Text(
                                                'Revocación / consultar estado',
                                              ),
                                            )
                                          else
                                            RevocationPanel(
                                              key: ValueKey((
                                                'revocation',
                                                widget.userId,
                                                _active,
                                                c.id,
                                              )),
                                              scope: RevocationScope(
                                                widget.userId,
                                                _active!,
                                                c.id,
                                              ),
                                              repository: widget.revocations!,
                                              onRevoked: () {
                                                if (!_revoked.contains(c.id)) {
                                                  setState(
                                                    () => _revoked.add(c.id),
                                                  );
                                                }
                                              },
                                              keys: widget.revocationKeys!,
                                              onSessionExpired:
                                                  widget.onSessionExpired,
                                              sessionChanges:
                                                  widget.sessionChanges,
                                            ),
                                        if (widget.anchoring != null &&
                                            widget.anchorStore != null &&
                                            selected.canIssue)
                                          if (_anchorId != c.id)
                                            TextButton(
                                              onPressed: () => setState(
                                                () => _anchorId = c.id,
                                              ),
                                              child: Text(
                                                _validity(c) ==
                                                        CertificateValidity
                                                            .valid
                                                    ? 'Solicitar anclaje / consultar operación'
                                                    : 'Consultar operación de anclaje',
                                              ),
                                            )
                                          else
                                            AnchoringPanel(
                                              key: ValueKey((
                                                widget.userId,
                                                _active,
                                                c.id,
                                              )),
                                              scope: AnchorScope(
                                                widget.userId,
                                                _active!,
                                                c.id,
                                              ),
                                              canRequest:
                                                  _validity(c) ==
                                                  CertificateValidity.valid,
                                              repository: widget.anchoring!,
                                              store: widget.anchorStore!,
                                              onSessionExpired:
                                                  widget.onSessionExpired,
                                              sessionChanges:
                                                  widget.sessionChanges,
                                            ),
                                        if (widget.openings != null &&
                                            selected.canIssue &&
                                            _openingId != c.id)
                                          TextButton(
                                            onPressed: () => setState(
                                              () => _openingId = c.id,
                                            ),
                                            child: const Text(
                                              'Consultar apertura privada',
                                            ),
                                          ),
                                        if (widget.openings != null &&
                                            widget.openingTransfer != null &&
                                            selected.canIssue &&
                                            _openingId == c.id)
                                          OpeningAction(
                                            key: ValueKey((
                                              'opening',
                                              widget.userId,
                                              _active,
                                              c.id,
                                            )),
                                            userId: widget.userId,
                                            certificateId: c.id,
                                            repository: widget.openings!,
                                            transfer: widget.openingTransfer!,
                                            onSessionExpired:
                                                widget.onSessionExpired,
                                            sessionChanges:
                                                widget.sessionChanges,
                                          ),
                                        if (widget.documents != null &&
                                            selected.canIssue &&
                                            _documentId != c.id)
                                          TextButton(
                                            onPressed: () => setState(
                                              () => _documentId = c.id,
                                            ),
                                            child: const Text('Consultar PDF'),
                                          ),
                                        if (widget.documents != null &&
                                            selected.canIssue &&
                                            _documentId == c.id)
                                          DocumentAction(
                                            key: ValueKey((
                                              widget.userId,
                                              _active,
                                              c.id,
                                            )),
                                            userId: widget.userId,
                                            certificateId: c.id,
                                            repository: widget.documents!,
                                            onSessionExpired:
                                                widget.onSessionExpired,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}
