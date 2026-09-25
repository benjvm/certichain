import 'package:mobile/features/profile/domain/profile_repository.dart';
import 'package:mobile/features/certificates/domain/certificate_repository.dart';

class FakeProfileRepository implements ProfileRepository {
  UserProfile? profile = const UserProfile(
    id: 'synthetic-user',
    fullName: 'Ana del perfil',
    role: 'holder',
  );
  Future<UserProfile?> Function(String)? handler;
  @override
  Future<UserProfile?> readProfile(String userId) async =>
      handler != null ? handler!(userId) : profile;
}

class FakeCertificateRepository implements CertificateRepository {
  CertificateWallet wallet = CertificateWallet(certificates: [], total: 0);
  Future<CertificateWallet> Function(String)? handler;
  @override
  Future<CertificateWallet> readWallet(String userId) async =>
      handler != null ? handler!(userId) : wallet;
}
