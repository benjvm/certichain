import '../domain/blockchain_verification.dart';
import '../../issuance/domain/anchoring_repository.dart';
import 'blockchain_models.dart';
import 'opening_file.dart';

class ProtocolOpeningTools implements OpeningInput, OpeningTransfer {
  final _file = OpeningFile();
  @override
  CertificateOpening parse(String json) => parseOpening(json);
  @override
  Future<String?> pickJson() => _file.pick();
  @override
  void cancel() => _file.cancel();
  @override
  String serialize(CertificateOpening opening) => encodeOpening(opening);
  @override
  Future<bool> export(CertificateOpening opening) =>
      saveOpening(serialize(opening));
}
