import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/app_update/data/gitee/dio_gitee_checksum_repository.dart';
import 'package:y300/features/app_update/data/gitee/dio_gitee_latest_release_repository.dart';
import 'package:y300/features/app_update/data/local/local_app_update_file_store.dart';
import 'package:y300/features/app_update/data/platform/background_downloader_binary_downloader.dart';
import 'package:y300/features/app_update/data/platform/crypto_app_update_artifact_verifier.dart';
import 'package:y300/features/app_update/data/platform/open_filex_app_update_installer.dart';
import 'package:y300/features/app_update/data/platform/permission_handler_app_update_install_permission.dart';
import 'package:y300/features/app_update/data/platform/url_launcher_app_update_launcher.dart';
import 'package:y300/features/app_update/domain/repositories/gitee_latest_release_repository.dart';
import 'package:y300/features/app_update/domain/repositories/app_update_checksum_repository.dart';
import 'package:y300/features/app_update/domain/services/app_update_binary_downloader.dart';
import 'package:y300/features/app_update/domain/services/app_update_artifact_verifier.dart';
import 'package:y300/features/app_update/domain/services/app_update_download_service.dart';
import 'package:y300/features/app_update/domain/services/app_update_file_store.dart';
import 'package:y300/features/app_update/domain/services/app_update_install_permission_gateway.dart';
import 'package:y300/features/app_update/domain/services/app_update_installer.dart';
import 'package:y300/features/app_update/domain/services/app_update_launcher.dart';
import 'package:y300/features/app_update/presentation/controllers/app_update_prompt_coordinator.dart';

final appUpdateDioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: DioGiteeLatestReleaseRepository.defaultRequestTimeout,
      sendTimeout: DioGiteeLatestReleaseRepository.defaultRequestTimeout,
      receiveTimeout: DioGiteeLatestReleaseRepository.defaultRequestTimeout,
    ),
  );
  ref.onDispose(() => dio.close(force: true));
  return dio;
});

final giteeLatestReleaseRepositoryProvider =
    Provider<GiteeLatestReleaseRepository>((ref) {
      return DioGiteeLatestReleaseRepository(
        dio: ref.watch(appUpdateDioProvider),
      );
    });

final appUpdateChecksumRepositoryProvider =
    Provider<AppUpdateChecksumRepository>((ref) {
      return DioGiteeChecksumRepository(dio: ref.watch(appUpdateDioProvider));
    });

final appUpdateFileStoreProvider = Provider<AppUpdateFileStore>((ref) {
  return LocalAppUpdateFileStore();
});

final appUpdateBinaryDownloaderProvider = Provider<AppUpdateBinaryDownloader>((
  ref,
) {
  final downloader = BackgroundDownloaderBinaryDownloader();
  ref.onDispose(() => unawaited(downloader.dispose()));
  return downloader;
});

final appUpdateInstallPermissionProvider =
    Provider<AppUpdateInstallPermissionGateway>((ref) {
      return const PermissionHandlerAppUpdateInstallPermission();
    });

final appUpdateInstallerProvider = Provider<AppUpdateInstaller>((ref) {
  return OpenFilexAppUpdateInstaller(
    fileStore: ref.watch(appUpdateFileStoreProvider),
    permissionGateway: ref.watch(appUpdateInstallPermissionProvider),
  );
});

final appUpdateDownloadServiceProvider = Provider<AppUpdateDownloadService>((
  ref,
) {
  final service = AppUpdateDownloadService(
    checksumRepository: ref.watch(appUpdateChecksumRepositoryProvider),
    binaryDownloader: ref.watch(appUpdateBinaryDownloaderProvider),
    verifier: ref.watch(appUpdateArtifactVerifierProvider),
    fileStore: ref.watch(appUpdateFileStoreProvider),
    installer: ref.watch(appUpdateInstallerProvider),
  );
  unawaited(service.restoreBackground());
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

final appUpdateArtifactVerifierProvider = Provider<AppUpdateArtifactVerifier>((
  ref,
) {
  return CryptoAppUpdateArtifactVerifier();
});

final appUpdateLauncherProvider = Provider<AppUpdateLauncher>((ref) {
  return UrlLauncherAppUpdateLauncher();
});

final appUpdatePromptCoordinatorProvider = Provider<AppUpdatePromptCoordinator>(
  (ref) {
    final logger = ref.watch(loggerProvider);
    final coordinator = AppUpdatePromptCoordinator(
      repository: ref.watch(giteeLatestReleaseRepositoryProvider),
      launcher: ref.watch(appUpdateLauncherProvider),
      downloadService: ref.watch(appUpdateDownloadServiceProvider),
      onStoreFailure: (failure) {
        logger.w(
          '[AppUpdate][store] code=${failure.code.name} '
          'field=${failure.field ?? '-'}',
        );
      },
    );
    ref.onDispose(coordinator.dispose);
    return coordinator;
  },
);
