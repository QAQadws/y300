import 'package:y300/features/app_update/domain/models/app_update_artifact.dart';
import 'package:y300/features/app_update/domain/models/app_update_binary_event.dart';

abstract interface class AppUpdateBinaryDownloader {
  Stream<AppUpdateBinaryEvent> download(
    AppUpdateArtifact artifact, {
    required String stagingPath,
  });

  Future<void> cancel();
}
