import 'dart:async';

import 'package:mobile/features/institutions/domain/institution_repository.dart';
import 'package:mobile/features/issuance/domain/issuance_repository.dart';
import 'package:mobile/features/certificates/domain/certificate_repository.dart';
import 'package:mobile/features/certificates/domain/certificate_document_repository.dart';

const actorId = '11111111-2222-3333-4444-555555555555';
const holderId = '99999999-aaaa-bbbb-cccc-dddddddddddd';
const institutionId = 'abcdefab-1234-5678-90ab-abcdefabcdef';
const certificateId = '01234567-89ab-cdef-0123-456789abcdef';
InstitutionMembership membership({
  String id = institutionId,
  String name = 'Institución de pruebas',
  InstitutionalRole role = InstitutionalRole.issuer,
  InstitutionStatus status = InstitutionStatus.verified,
}) => InstitutionMembership(id: id, name: name, role: role, status: status);
SelectedPdf selectedPdf() =>
    SelectedPdf(name: 'certificado.pdf', bytes: [37, 80, 68, 70, 1, 2, 3]);
IssuanceData issuanceData() =>
    IssuanceData(holderId: holderId, title: 'Título de pruebas');

class MemoryAttempts implements PendingAttemptStore {
  final values = <(String, String), PendingAttempt>{};
  bool fail = false;
  @override
  Future<PendingAttempt?> read(String userId, String institutionId) async =>
      values[(userId, institutionId)];
  @override
  Future<void> save(
    String userId,
    String institutionId,
    PendingAttempt attempt,
  ) async {
    if (fail) throw StateError('private');
    values[(userId, institutionId)] = attempt;
  }

  @override
  Future<void> clear(String userId, String institutionId) async {
    values.remove((userId, institutionId));
  }
}

class FakeIssuance implements IssuanceRepository {
  final requests = <IssuanceRequest>[];
  IssuanceException? error;
  Completer<String>? pending;
  @override
  Future<String> issue(IssuanceRequest request) async {
    requests.add(request);
    if (pending != null) return pending!.future;
    if (error != null) throw error!;
    return certificateId;
  }
}

class FakePdfPicker implements PdfPicker {
  SelectedPdf? pdf = selectedPdf();
  @override
  Future<SelectedPdf?> pick() async => pdf;
}

class FakeInstitutions implements InstitutionRepository {
  List<InstitutionMembership> members = [membership()];
  Object? error;
  final reads = <String>[];
  final wallets = <String, CertificateWallet>{};
  @override
  Future<List<InstitutionMembership>> readMemberships(String userId) async {
    if (error != null) throw error!;
    return members;
  }

  @override
  Future<CertificateWallet> readIssued(String institutionId) async {
    reads.add(institutionId);
    if (error != null) throw error!;
    return wallets[institutionId] ??
        CertificateWallet(certificates: [], total: 0);
  }
}

class FakeDocuments implements CertificateDocumentRepository {
  bool available = true;
  int checks = 0, downloads = 0;
  Object? error;
  @override
  Future<bool> isAvailable(String userId, String certificateId) async {
    checks++;
    if (error != null) throw error!;
    return available;
  }

  @override
  Future<bool> download(String userId, String certificateId) async {
    downloads++;
    if (error != null) throw error!;
    return true;
  }
}
