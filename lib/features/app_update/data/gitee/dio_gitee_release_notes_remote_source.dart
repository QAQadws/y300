import 'dart:async';
import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:dio/dio.dart';
import 'package:version/version.dart';
import 'package:y300/features/app_update/data/gitee/gitee_release_parser.dart';
import 'package:y300/features/app_update/domain/models/app_release_notes.dart';
import 'package:y300/features/app_update/domain/models/app_release_notes_load_result.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/repositories/app_release_notes_remote_source.dart';
import 'package:y300/features/app_update/domain/services/app_version_codec.dart';

final class DioGiteeReleaseNotesRemoteSource
    implements AppReleaseNotesRemoteSource {
  DioGiteeReleaseNotesRemoteSource({
    required Dio dio,
    AppVersionCodec versionCodec = const AppVersionCodec(),
    DateTime Function()? now,
    this.requestTimeout = defaultRequestTimeout,
  }) : _dio = dio,
       _versionCodec = versionCodec,
       _now = now ?? DateTime.now;

  static const Duration defaultRequestTimeout = Duration(seconds: 10);

  final Dio _dio;
  final AppVersionCodec _versionCodec;
  final DateTime Function() _now;
  final Duration requestTimeout;

  Uri releaseUri(Version version) {
    return Uri.https(
      'gitee.com',
      '/api/v5/repos/QAQadws/y300-releases/releases/tags/'
          '${_versionCodec.canonicalTag(version)}',
    );
  }

  @override
  Future<AppReleaseNotesLoadResult> fetch(Version version) async {
    try {
      final response = await _dio
          .getUri<Object?>(
            releaseUri(version),
            options: Options(
              responseType: ResponseType.plain,
              headers: const <String, String>{
                Headers.acceptHeader: Headers.jsonContentType,
              },
              validateStatus: (_) => true,
            ),
          )
          .timeout(requestTimeout);
      return _handleResponse(version, response);
    } on TimeoutException {
      return _failure(
        AppUpdateFailureCode.requestTimeout,
        'Gitee release notes request timed out.',
      );
    } on DioException catch (error) {
      return _mapDioFailure(error);
    } on Object {
      return _failure(
        AppUpdateFailureCode.remoteUnavailable,
        'Gitee release notes request failed unexpectedly.',
      );
    }
  }

  AppReleaseNotesLoadResult _handleResponse(
    Version requestedVersion,
    Response<Object?> response,
  ) {
    if (response.statusCode != 200) {
      return _failureForStatusCode(response.statusCode);
    }

    Object? payload = response.data;
    if (payload is String) {
      try {
        payload = jsonDecode(payload);
      } on FormatException {
        return _failure(
          AppUpdateFailureCode.invalidPayload,
          'Gitee release notes response is not valid JSON.',
        );
      }
    }
    if (payload is! Map) {
      return _failure(
        AppUpdateFailureCode.invalidPayload,
        'Gitee release notes response must be an object.',
      );
    }

    final tagValue = payload['tag_name'];
    final prereleaseValue = payload['prerelease'];
    final bodyValue = payload['body'];
    if (tagValue is! String) {
      return _fieldFailure('tag_name', 'Release tag is missing or invalid.');
    }
    if (prereleaseValue is! bool) {
      return _fieldFailure(
        'prerelease',
        'Release prerelease state is missing or invalid.',
      );
    }
    if (bodyValue != null && bodyValue is! String) {
      return _fieldFailure('body', 'Release notes body must be text.');
    }

    final responseVersion = _versionCodec.parseReleaseTag(tagValue);
    if (responseVersion == null || responseVersion != requestedVersion) {
      return _failure(
        AppUpdateFailureCode.invalidTag,
        'Gitee release notes tag does not match the installed version.',
        field: 'tag_name',
      );
    }
    if (prereleaseValue) {
      return _failure(
        AppUpdateFailureCode.prerelease,
        'Prerelease notes are not supported.',
        field: 'prerelease',
      );
    }

    final bodyCharacters = (bodyValue as String? ?? '').characters;
    final body =
        bodyCharacters.length <= GiteeReleaseParser.maxReleaseNotesCharacters
        ? bodyCharacters.toString()
        : bodyCharacters
              .take(GiteeReleaseParser.maxReleaseNotesCharacters)
              .toString();
    return AppReleaseNotesAvailable(
      AppReleaseNotes(
        version: requestedVersion,
        tag: tagValue,
        body: body,
        fetchedAt: _now().toUtc(),
      ),
    );
  }

  AppReleaseNotesLoadResult _mapDioFailure(DioException error) {
    final statusCode = error.response?.statusCode;
    if (statusCode != null) {
      return _failureForStatusCode(statusCode);
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => _failure(
        AppUpdateFailureCode.requestTimeout,
        'Gitee release notes request timed out.',
      ),
      DioExceptionType.connectionError => _failure(
        AppUpdateFailureCode.networkUnavailable,
        'Gitee release notes could not be reached.',
      ),
      _ => _failure(
        AppUpdateFailureCode.remoteUnavailable,
        'Gitee release notes request failed.',
      ),
    };
  }

  AppReleaseNotesLoadResult _failureForStatusCode(int? statusCode) {
    return switch (statusCode) {
      404 => _failure(
        AppUpdateFailureCode.releaseNotFound,
        'The installed release was not found.',
      ),
      429 => _failure(
        AppUpdateFailureCode.rateLimited,
        'Gitee release notes request was rate limited.',
      ),
      _ => _failure(
        AppUpdateFailureCode.remoteUnavailable,
        'Gitee release notes returned HTTP ${statusCode ?? 'unknown'}.',
      ),
    };
  }

  AppReleaseNotesLoadResult _fieldFailure(String field, String message) {
    return _failure(
      AppUpdateFailureCode.invalidFieldType,
      message,
      field: field,
    );
  }

  AppReleaseNotesLoadResult _failure(
    AppUpdateFailureCode code,
    String message, {
    String? field,
  }) {
    return AppReleaseNotesUnavailable(
      failure: AppUpdateFailure(code: code, message: message, field: field),
    );
  }
}
