import 'package:y300/features/app_update/domain/models/app_update_artifact_identity.dart';

abstract interface class AppUpdateFileStore {
  Future<String> stagingPath(AppUpdateArtifactIdentity identity);

  Future<String> verifiedPath(AppUpdateArtifactIdentity identity);

  Future<bool> exists(String path);

  Stream<List<int>> openRead(String path);

  Future<void> promote({
    required String stagingPath,
    required String verifiedPath,
  });

  Future<void> deleteArtifact(AppUpdateArtifactIdentity identity);

  Future<void> cleanupStaleArtifacts();
}
