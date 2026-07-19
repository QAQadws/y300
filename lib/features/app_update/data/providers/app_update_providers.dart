import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/app_update/data/gitee/dio_gitee_checksum_repository.dart';
import 'package:y300/features/app_update/data/gitee/dio_gitee_latest_release_repository.dart';
import 'package:y300/features/app_update/data/local/local_app_update_file_store.dart';
import 'package:y300/features/app_update/data/platform/dio_app_update_binary_downloader.dart';
import 'package:y300/features/app_update/data/platform/url_launcher_app_update_launcher.dart';
import 'package:y300/features/app_update/domain/repositories/gitee_latest_release_repository.dart';
import 'package:y300/features/app_update/domain/repositories/app_update_checksum_repository.dart';
import 'package:y300/features/app_update/domain/services/app_update_binary_downloader.dart';
import 'package:y300/features/app_update/domain/services/app_update_file_store.dart';
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
  final downloader = DioAppUpdateBinaryDownloader(
    dio: ref.watch(appUpdateDioProvider),
  );
  ref.onDispose(() => unawaited(downloader.dispose()));
  return downloader;
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
