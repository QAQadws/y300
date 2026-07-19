import 'dart:async';

import 'package:dio/dio.dart';
import 'package:y300/features/app_update/data/gitee/app_update_checksum_parser.dart';
import 'package:y300/features/app_update/domain/models/app_update_artifact.dart';
import 'package:y300/features/app_update/domain/models/app_update_checksum_lookup_result.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/repositories/app_update_checksum_repository.dart';
import 'package:y300/features/app_update/domain/services/app_update_apk_uri_policy.dart';

final class DioGiteeChecksumRepository implements AppUpdateChecksumRepository {
  DioGiteeChecksumRepository({
    required Dio dio,
    AppUpdateChecksumParser parser = const AppUpdateChecksumParser(),
    AppUpdateApkUriPolicy uriPolicy = const AppUpdateApkUriPolicy(),
    this.requestTimeout = defaultRequestTimeout,
  }) : _dio = dio,
       _parser = parser,
       _uriPolicy = uriPolicy;

  static const Duration defaultRequestTimeout = Duration(seconds: 10);

  final Dio _dio;
  final AppUpdateChecksumParser _parser;
  final AppUpdateApkUriPolicy _uriPolicy;
  final Duration requestTimeout;
  final Map<String, Future<AppUpdateChecksumLookupResult>> _inFlight =
      <String, Future<AppUpdateChecksumLookupResult>>{};

  @override
  Future<AppUpdateChecksumLookupResult> fetchChecksum(
    AppUpdateArtifact artifact,
  ) {
    final key = artifact.identityKey;
    final existing = _inFlight[key];
    if (existing != null) {
      return existing;
    }

    final request = _fetchChecksum(artifact);
    _inFlight[key] = request;
    request.whenComplete(() {
      if (identical(_inFlight[key], request)) {
        _inFlight.remove(key);
      }
    });
    return request;
  }

  Future<AppUpdateChecksumLookupResult> _fetchChecksum(
    AppUpdateArtifact artifact,
  ) async {
    if (!_uriPolicy.isAllowedReleaseAsset(
      artifact.checksumUri,
      expectedName: artifact.checksumFileName,
    )) {
      return const AppUpdateChecksumLookupFailure(
        AppUpdateFailure(
          code: AppUpdateFailureCode.invalidChecksumAssetUrl,
          message: 'The checksum URL is not an allowed Gitee release asset.',
        ),
      );
    }

    try {
      final response = await _dio
          .getUri<Object?>(
            artifact.checksumUri,
            options: Options(
              responseType: ResponseType.plain,
              headers: const <String, String>{
                Headers.acceptHeader: 'text/plain',
              },
              validateStatus: (_) => true,
            ),
          )
          .timeout(requestTimeout);
      if (response.statusCode != 200) {
        final statusCode = response.statusCode;
        return AppUpdateChecksumLookupFailure(
          AppUpdateFailure(
            code: _failureCodeForStatus(statusCode ?? 0),
            message:
                'The Gitee checksum request returned HTTP ${response.statusCode ?? 'unknown'}.',
          ),
        );
      }
      final raw = response.data;
      if (raw is! String) {
        return AppUpdateChecksumLookupFailure(
          AppUpdateFailure(
            code: AppUpdateFailureCode.checksumMalformed,
            message:
                'The Gitee checksum response is not plain text '
                '(${raw.runtimeType}).',
          ),
        );
      }
      return switch (_parser.parse(raw, expectedFileName: artifact.fileName)) {
        AppUpdateChecksumParseSuccess(:final checksum) =>
          AppUpdateChecksumLookupSuccess(checksum),
        AppUpdateChecksumParseFailure(:final failure) =>
          AppUpdateChecksumLookupFailure(failure),
      };
    } on TimeoutException {
      return const AppUpdateChecksumLookupFailure(
        AppUpdateFailure(
          code: AppUpdateFailureCode.requestTimeout,
          message: 'The Gitee checksum request timed out.',
        ),
      );
    } on DioException catch (error) {
      return AppUpdateChecksumLookupFailure(_mapDioFailure(error));
    } on Object {
      return const AppUpdateChecksumLookupFailure(
        AppUpdateFailure(
          code: AppUpdateFailureCode.checksumRequestFailed,
          message: 'The Gitee checksum request failed unexpectedly.',
        ),
      );
    }
  }

  AppUpdateFailure _mapDioFailure(DioException error) {
    final statusCode = error.response?.statusCode;
    if (statusCode != null) {
      return AppUpdateFailure(
        code: _failureCodeForStatus(statusCode),
        message: 'The Gitee checksum request returned HTTP $statusCode.',
      );
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => const AppUpdateFailure(
        code: AppUpdateFailureCode.requestTimeout,
        message: 'The Gitee checksum request timed out.',
      ),
      DioExceptionType.connectionError => const AppUpdateFailure(
        code: AppUpdateFailureCode.networkUnavailable,
        message: 'The Gitee checksum could not be reached.',
      ),
      _ => AppUpdateFailure(
        code: AppUpdateFailureCode.checksumRequestFailed,
        message: 'The Gitee checksum request failed (${error.type.name}).',
      ),
    };
  }

  AppUpdateFailureCode _failureCodeForStatus(int statusCode) {
    return switch (statusCode) {
      404 => AppUpdateFailureCode.checksumAssetMissing,
      429 => AppUpdateFailureCode.rateLimited,
      >= 500 && <= 599 => AppUpdateFailureCode.remoteUnavailable,
      _ => AppUpdateFailureCode.checksumRequestFailed,
    };
  }
}
