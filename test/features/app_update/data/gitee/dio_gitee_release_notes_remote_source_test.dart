import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:version/version.dart';
import 'package:y300/features/app_update/data/gitee/dio_gitee_release_notes_remote_source.dart';
import 'package:y300/features/app_update/domain/models/app_release_notes_load_result.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';

void main() {
  final version = Version.parse('0.0.6');

  test('loads notes by the exact installed release tag', () async {
    final adapter = _RecordingAdapter(
      (_) async => _jsonResponse(<String, Object?>{
        'tag_name': 'v0.0.6',
        'prerelease': false,
        'body': 'Current release notes',
      }, statusCode: 200),
    );
    final source = _source(adapter);

    final result = await source.fetch(version);

    expect(result, isA<AppReleaseNotesAvailable>());
    expect(
      (result as AppReleaseNotesAvailable).notes.body,
      'Current release notes',
    );
    expect(
      adapter.lastOptions?.uri.path,
      '/api/v5/repos/QAQadws/y300-releases/releases/tags/v0.0.6',
    );
    expect(adapter.lastOptions?.headers, isNot(contains('cookie')));
  });

  test('persists an empty body as a successful release lookup', () async {
    final source = _source(
      _RecordingAdapter(
        (_) async => _jsonResponse(<String, Object?>{
          'tag_name': 'v0.0.6',
          'prerelease': false,
          'body': null,
        }, statusCode: 200),
      ),
    );

    final result = await source.fetch(version);

    expect(result, isA<AppReleaseNotesAvailable>());
    expect((result as AppReleaseNotesAvailable).notes.body, isEmpty);
  });

  test('rejects mismatched tags and prereleases', () async {
    final mismatched = await _source(
      _RecordingAdapter(
        (_) async => _jsonResponse(<String, Object?>{
          'tag_name': 'v0.0.5',
          'prerelease': false,
          'body': '',
        }, statusCode: 200),
      ),
    ).fetch(version);
    final prerelease = await _source(
      _RecordingAdapter(
        (_) async => _jsonResponse(<String, Object?>{
          'tag_name': 'v0.0.6',
          'prerelease': true,
          'body': '',
        }, statusCode: 200),
      ),
    ).fetch(version);

    expect(_failureCode(mismatched), AppUpdateFailureCode.invalidTag);
    expect(_failureCode(prerelease), AppUpdateFailureCode.prerelease);
  });

  test(
    'maps status, malformed payload, connection, and timeout failures',
    () async {
      for (final entry in <(int, AppUpdateFailureCode)>[
        (404, AppUpdateFailureCode.releaseNotFound),
        (429, AppUpdateFailureCode.rateLimited),
        (500, AppUpdateFailureCode.remoteUnavailable),
      ]) {
        final result = await _source(
          _RecordingAdapter(
            (_) async =>
                _jsonResponse(<String, Object?>{}, statusCode: entry.$1),
          ),
        ).fetch(version);
        expect(_failureCode(result), entry.$2);
      }

      final malformed = await _source(
        _RecordingAdapter(
          (_) async => ResponseBody.fromString('{invalid', 200),
        ),
      ).fetch(version);
      expect(_failureCode(malformed), AppUpdateFailureCode.invalidPayload);

      final connection = await _source(
        _RecordingAdapter((options) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          );
        }),
      ).fetch(version);
      expect(_failureCode(connection), AppUpdateFailureCode.networkUnavailable);

      final response = Completer<ResponseBody>();
      final timeoutSource = _source(
        _RecordingAdapter((_) => response.future),
        requestTimeout: const Duration(milliseconds: 1),
      );
      final timeout = await timeoutSource.fetch(version);
      response.complete(_jsonResponse(<String, Object?>{}, statusCode: 200));
      expect(_failureCode(timeout), AppUpdateFailureCode.requestTimeout);
    },
  );
}

DioGiteeReleaseNotesRemoteSource _source(
  HttpClientAdapter adapter, {
  Duration requestTimeout = const Duration(seconds: 10),
}) {
  final dio = Dio()..httpClientAdapter = adapter;
  return DioGiteeReleaseNotesRemoteSource(
    dio: dio,
    requestTimeout: requestTimeout,
    now: () => DateTime.utc(2026, 7, 22),
  );
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

AppUpdateFailureCode _failureCode(AppReleaseNotesLoadResult result) {
  expect(result, isA<AppReleaseNotesUnavailable>());
  return (result as AppReleaseNotesUnavailable).failure.code;
}

final class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this._handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) _handler;
  RequestOptions? lastOptions;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    return _handler(options);
  }
}
