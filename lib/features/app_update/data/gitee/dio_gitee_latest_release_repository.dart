import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:y300/features/app_update/data/gitee/gitee_release_parser.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/models/gitee_release_candidate.dart';
import 'package:y300/features/app_update/domain/models/gitee_release_lookup_result.dart';
import 'package:y300/features/app_update/domain/repositories/gitee_latest_release_repository.dart';

final class DioGiteeLatestReleaseRepository
    implements GiteeLatestReleaseRepository {
  DioGiteeLatestReleaseRepository({
    required Dio dio,
    GiteeReleaseParser parser = const GiteeReleaseParser(),
    DateTime Function()? now,
    this.successTtl = defaultSuccessTtl,
    this.failureBackoff = defaultFailureBackoff,
    this.requestTimeout = defaultRequestTimeout,
  }) : _dio = dio,
       _parser = parser,
       _now = now ?? DateTime.now;

  static final Uri latestReleaseUri = Uri.https(
    'gitee.com',
    '/api/v5/repos/QAQadws/y300-releases/releases/latest',
  );
  static const Duration defaultSuccessTtl = Duration(hours: 6);
  static const Duration defaultFailureBackoff = Duration(minutes: 5);
  static const Duration defaultRequestTimeout = Duration(seconds: 10);

  final Dio _dio;
  final GiteeReleaseParser _parser;
  final DateTime Function() _now;
  final Duration successTtl;
  final Duration failureBackoff;
  final Duration requestTimeout;

  GiteeReleaseCandidate? _cachedCandidate;
  DateTime? _successAt;
  AppUpdateFailure? _cachedFailure;
  DateTime? _failureAt;
  Future<GiteeReleaseLookupResult>? _inFlight;

  @override
  Future<GiteeReleaseLookupResult> getLatest({
    bool forceRefresh = false,
  }) async {
    final now = _now().toUtc();
    if (!forceRefresh) {
      final cached = _readCache(now);
      if (cached != null) {
        return cached;
      }
    }

    final inFlight = _inFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final request = _fetchLatest();
    _inFlight = request;
    try {
      return await request;
    } finally {
      if (identical(_inFlight, request)) {
        _inFlight = null;
      }
    }
  }

  GiteeReleaseLookupResult? _readCache(DateTime now) {
    if (_cachedFailure case final failure?
        when _isFresh(
          recordedAt: _failureAt,
          now: now,
          lifetime: failureBackoff,
        )) {
      return GiteeReleaseLookupFailure(
        failure: failure,
        source: GiteeReleaseLookupSource.cache,
      );
    }
    if (_cachedCandidate case final candidate?
        when _isFresh(recordedAt: _successAt, now: now, lifetime: successTtl)) {
      return GiteeReleaseLookupSuccess(
        candidate: candidate,
        source: GiteeReleaseLookupSource.cache,
      );
    }
    return null;
  }

  bool _isFresh({
    required DateTime? recordedAt,
    required DateTime now,
    required Duration lifetime,
  }) {
    if (recordedAt == null) {
      return false;
    }
    final age = now.difference(recordedAt);
    return !age.isNegative && age < lifetime;
  }

  Future<GiteeReleaseLookupResult> _fetchLatest() async {
    try {
      final response = await _dio
          .getUri<Object?>(
            latestReleaseUri,
            options: Options(
              responseType: ResponseType.plain,
              headers: const <String, String>{
                Headers.acceptHeader: Headers.jsonContentType,
              },
              validateStatus: (_) => true,
            ),
          )
          .timeout(requestTimeout);
      return _handleResponse(response);
    } on TimeoutException {
      return _recordFailure(
        const AppUpdateFailure(
          code: AppUpdateFailureCode.requestTimeout,
          message: 'Gitee latest release request timed out.',
        ),
      );
    } on DioException catch (error) {
      return _recordFailure(_mapDioFailure(error));
    } on Object {
      return _recordFailure(
        const AppUpdateFailure(
          code: AppUpdateFailureCode.remoteUnavailable,
          message: 'Gitee latest release request failed unexpectedly.',
        ),
      );
    }
  }

  GiteeReleaseLookupResult _handleResponse(Response<Object?> response) {
    final statusCode = response.statusCode;
    if (statusCode != 200) {
      return _recordFailure(_failureForStatusCode(statusCode));
    }

    Object? payload = response.data;
    if (payload is String) {
      try {
        payload = jsonDecode(payload);
      } on FormatException {
        return _recordFailure(
          const AppUpdateFailure(
            code: AppUpdateFailureCode.invalidPayload,
            message: 'Gitee latest release response is not valid JSON.',
          ),
        );
      }
    }

    return switch (_parser.parse(payload)) {
      GiteeReleaseParseSuccess(:final candidate) => _recordSuccess(candidate),
      GiteeReleaseParseFailure(:final failure) => _recordFailure(failure),
    };
  }

  GiteeReleaseLookupSuccess _recordSuccess(GiteeReleaseCandidate candidate) {
    _cachedCandidate = candidate;
    _successAt = _now().toUtc();
    _cachedFailure = null;
    _failureAt = null;
    return GiteeReleaseLookupSuccess(
      candidate: candidate,
      source: GiteeReleaseLookupSource.network,
    );
  }

  GiteeReleaseLookupFailure _recordFailure(AppUpdateFailure failure) {
    _cachedFailure = failure;
    _failureAt = _now().toUtc();
    _cachedCandidate = null;
    _successAt = null;
    return GiteeReleaseLookupFailure(
      failure: failure,
      source: GiteeReleaseLookupSource.network,
    );
  }

  AppUpdateFailure _mapDioFailure(DioException error) {
    if (error.error is FormatException) {
      return const AppUpdateFailure(
        code: AppUpdateFailureCode.invalidPayload,
        message: 'Gitee latest release response is not valid JSON.',
      );
    }
    final statusCode = error.response?.statusCode;
    if (statusCode != null) {
      return _failureForStatusCode(statusCode);
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => const AppUpdateFailure(
        code: AppUpdateFailureCode.requestTimeout,
        message: 'Gitee latest release request timed out.',
      ),
      DioExceptionType.connectionError => const AppUpdateFailure(
        code: AppUpdateFailureCode.networkUnavailable,
        message: 'Gitee latest release could not be reached.',
      ),
      _ => const AppUpdateFailure(
        code: AppUpdateFailureCode.remoteUnavailable,
        message: 'Gitee latest release request failed.',
      ),
    };
  }

  AppUpdateFailure _failureForStatusCode(int? statusCode) {
    return switch (statusCode) {
      404 => const AppUpdateFailure(
        code: AppUpdateFailureCode.releaseNotFound,
        message: 'Gitee latest release was not found.',
      ),
      429 => const AppUpdateFailure(
        code: AppUpdateFailureCode.rateLimited,
        message: 'Gitee latest release request was rate limited.',
      ),
      _ => AppUpdateFailure(
        code: AppUpdateFailureCode.remoteUnavailable,
        message:
            'Gitee latest release returned HTTP ${statusCode ?? 'unknown'}.',
      ),
    };
  }
}
