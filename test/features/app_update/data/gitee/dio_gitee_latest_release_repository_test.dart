import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/app_update/data/gitee/dio_gitee_latest_release_repository.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/models/gitee_release_lookup_result.dart';

import '../../test_support/gitee_release_phase0_fixture.dart';

void main() {
  group('DioGiteeLatestReleaseRepository', () {
    test(
      'loads the public latest endpoint and caches success for six hours',
      () async {
        final payload = await loadGiteeLatestReleaseV001Fixture();
        final adapter = _RecordingAdapter(
          (_) async => _jsonResponse(payload, statusCode: 200),
        );
        var now = DateTime.utc(2026, 7, 19, 0);
        final repository = _repository(adapter, now: () => now);

        final first = await repository.getLatest();
        final cached = await repository.getLatest();
        now = now.add(const Duration(hours: 6));
        final refreshed = await repository.getLatest();

        expect(first, isA<GiteeReleaseLookupSuccess>());
        expect(
          (first as GiteeReleaseLookupSuccess).source,
          GiteeReleaseLookupSource.network,
        );
        expect(cached, isA<GiteeReleaseLookupSuccess>());
        expect(
          (cached as GiteeReleaseLookupSuccess).source,
          GiteeReleaseLookupSource.cache,
        );
        expect(refreshed, isA<GiteeReleaseLookupSuccess>());
        expect(adapter.callCount, 2);
        expect(
          adapter.lastOptions?.uri,
          DioGiteeLatestReleaseRepository.latestReleaseUri,
        );
        expect(
          adapter.lastOptions?.headers[Headers.acceptHeader],
          Headers.jsonContentType,
        );
        expect(adapter.lastOptions?.headers, isNot(contains('cookie')));
        expect(adapter.lastOptions?.headers, isNot(contains('authorization')));
      },
    );

    test('force refresh bypasses a fresh success cache', () async {
      final payload = await loadGiteeLatestReleaseV001Fixture();
      final adapter = _RecordingAdapter(
        (_) async => _jsonResponse(payload, statusCode: 200),
      );
      final repository = _repository(adapter);

      await repository.getLatest();
      final refreshed = await repository.getLatest(forceRefresh: true);

      expect(refreshed, isA<GiteeReleaseLookupSuccess>());
      expect(adapter.callCount, 2);
    });

    test(
      'backs off failures for five minutes and retries afterwards',
      () async {
        final payload = await loadGiteeLatestReleaseV001Fixture();
        late _RecordingAdapter adapter;
        adapter = _RecordingAdapter((_) async {
          if (adapter.callCount == 1) {
            return _jsonResponse(<String, Object?>{}, statusCode: 429);
          }
          return _jsonResponse(payload, statusCode: 200);
        });
        var now = DateTime.utc(2026, 7, 19, 0);
        final repository = _repository(adapter, now: () => now);

        final first = await repository.getLatest();
        final cached = await repository.getLatest();
        now = now.add(const Duration(minutes: 5));
        final retried = await repository.getLatest();

        expect(_failureCode(first), AppUpdateFailureCode.rateLimited);
        expect(_failureCode(cached), AppUpdateFailureCode.rateLimited);
        expect(
          (cached as GiteeReleaseLookupFailure).source,
          GiteeReleaseLookupSource.cache,
        );
        expect(retried, isA<GiteeReleaseLookupSuccess>());
        expect(adapter.callCount, 2);
      },
    );

    test('coalesces concurrent normal and forced lookups', () async {
      final payload = await loadGiteeLatestReleaseV001Fixture();
      final response = Completer<ResponseBody>();
      final adapter = _RecordingAdapter((_) => response.future);
      final repository = _repository(adapter);

      final first = repository.getLatest();
      final second = repository.getLatest(forceRefresh: true);
      await adapter.firstCall;

      expect(adapter.callCount, 1);
      response.complete(_jsonResponse(payload, statusCode: 200));
      expect(await first, isA<GiteeReleaseLookupSuccess>());
      expect(await second, isA<GiteeReleaseLookupSuccess>());
      expect(adapter.callCount, 1);
    });

    test('maps HTTP and connection failures to stable codes', () async {
      for (final entry in <(int, AppUpdateFailureCode)>[
        (404, AppUpdateFailureCode.releaseNotFound),
        (429, AppUpdateFailureCode.rateLimited),
        (500, AppUpdateFailureCode.remoteUnavailable),
      ]) {
        final adapter = _RecordingAdapter(
          (_) async => _jsonResponse(<String, Object?>{}, statusCode: entry.$1),
        );
        final result = await _repository(adapter).getLatest();
        expect(_failureCode(result), entry.$2);
      }

      final connectionAdapter = _RecordingAdapter((options) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: 'offline',
        );
      });
      final result = await _repository(connectionAdapter).getLatest();
      expect(_failureCode(result), AppUpdateFailureCode.networkUnavailable);
    });

    test('maps request timeout to a stable failure', () async {
      final response = Completer<ResponseBody>();
      final adapter = _RecordingAdapter((_) => response.future);
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = DioGiteeLatestReleaseRepository(
        dio: dio,
        requestTimeout: const Duration(milliseconds: 1),
      );

      final result = await repository.getLatest();
      response.complete(_jsonResponse(<String, Object?>{}, statusCode: 200));

      expect(_failureCode(result), AppUpdateFailureCode.requestTimeout);
    });

    test('classifies malformed JSON without throwing', () async {
      final adapter = _RecordingAdapter(
        (_) async => ResponseBody.fromString(
          '{not-json',
          200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>[Headers.jsonContentType],
          },
        ),
      );

      final result = await _repository(adapter).getLatest();

      expect(_failureCode(result), AppUpdateFailureCode.invalidPayload);
    });
  });
}

DioGiteeLatestReleaseRepository _repository(
  HttpClientAdapter adapter, {
  DateTime Function()? now,
}) {
  final dio = Dio()..httpClientAdapter = adapter;
  return DioGiteeLatestReleaseRepository(dio: dio, now: now);
}

ResponseBody _jsonResponse(Object? value, {required int statusCode}) {
  return ResponseBody.fromString(
    jsonEncode(value),
    statusCode,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );
}

AppUpdateFailureCode _failureCode(GiteeReleaseLookupResult result) {
  expect(result, isA<GiteeReleaseLookupFailure>());
  return (result as GiteeReleaseLookupFailure).failure.code;
}

final class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this._handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) _handler;
  final Completer<void> _firstCall = Completer<void>();
  int callCount = 0;
  RequestOptions? lastOptions;

  Future<void> get firstCall => _firstCall.future;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    callCount += 1;
    lastOptions = options;
    if (!_firstCall.isCompleted) {
      _firstCall.complete();
    }
    return _handler(options);
  }
}
