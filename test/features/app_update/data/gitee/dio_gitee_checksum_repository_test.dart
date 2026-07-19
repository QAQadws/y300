import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/app_update/data/gitee/dio_gitee_checksum_repository.dart';
import 'package:y300/features/app_update/data/gitee/gitee_release_parser.dart';
import 'package:y300/features/app_update/domain/models/app_update_artifact.dart';
import 'package:y300/features/app_update/domain/models/app_update_checksum_lookup_result.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';

import '../../test_support/gitee_release_phase0_fixture.dart';

void main() {
  test(
    'fetches plain checksum text without business authentication headers',
    () async {
      final artifact = await _fixtureArtifact();
      final checksum = await loadGiteeLatestReleaseV001ChecksumFixture();
      final adapter = _RecordingAdapter(
        (_) async => ResponseBody.fromString(checksum, 200),
      );
      final repository = DioGiteeChecksumRepository(
        dio: Dio()..httpClientAdapter = adapter,
      );

      final result = await repository.fetchChecksum(artifact);

      expect(result, isA<AppUpdateChecksumLookupSuccess>());
      expect(
        (result as AppUpdateChecksumLookupSuccess).checksum.fileName,
        artifact.fileName,
      );
      expect(adapter.lastOptions?.uri, artifact.checksumUri);
      expect(adapter.lastOptions?.headers[Headers.acceptHeader], 'text/plain');
      expect(adapter.lastOptions?.headers, isNot(contains('cookie')));
      expect(adapter.lastOptions?.headers, isNot(contains('authorization')));
    },
  );

  test('coalesces concurrent checksum requests for one artifact', () async {
    final artifact = await _fixtureArtifact();
    final checksum = await loadGiteeLatestReleaseV001ChecksumFixture();
    final response = Completer<ResponseBody>();
    final adapter = _RecordingAdapter((_) => response.future);
    final repository = DioGiteeChecksumRepository(
      dio: Dio()..httpClientAdapter = adapter,
    );

    final first = repository.fetchChecksum(artifact);
    final second = repository.fetchChecksum(artifact);
    await adapter.firstCall;

    expect(adapter.callCount, 1);
    response.complete(ResponseBody.fromString(checksum, 200));
    expect(await first, isA<AppUpdateChecksumLookupSuccess>());
    expect(await second, isA<AppUpdateChecksumLookupSuccess>());
  });

  test('maps checksum HTTP failures to stable codes', () async {
    final artifact = await _fixtureArtifact();
    for (final entry in <(int, AppUpdateFailureCode)>[
      (404, AppUpdateFailureCode.checksumAssetMissing),
      (429, AppUpdateFailureCode.rateLimited),
      (503, AppUpdateFailureCode.remoteUnavailable),
    ]) {
      final adapter = _RecordingAdapter(
        (_) async => ResponseBody.fromString('', entry.$1),
      );
      final repository = DioGiteeChecksumRepository(
        dio: Dio()..httpClientAdapter = adapter,
      );

      final result = await repository.fetchChecksum(artifact);

      expect(result, isA<AppUpdateChecksumLookupFailure>());
      expect((result as AppUpdateChecksumLookupFailure).failure.code, entry.$2);
    }
  });
}

Future<AppUpdateArtifact> _fixtureArtifact() async {
  final parsed = GiteeReleaseParser().parse(
    await loadGiteeLatestReleaseV001Fixture(),
  );
  return AppUpdateArtifact.fromCandidate(
    (parsed as GiteeReleaseParseSuccess).candidate,
  );
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
