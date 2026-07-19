import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/app_update/data/gitee/gitee_release_parser.dart';
import 'package:y300/features/app_update/data/platform/dio_app_update_binary_downloader.dart';
import 'package:y300/features/app_update/domain/models/app_update_artifact.dart';
import 'package:y300/features/app_update/domain/models/app_update_binary_event.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';

import '../../test_support/gitee_release_phase0_fixture.dart';

void main() {
  test('writes a zip response to the canonical APK staging path', () async {
    final artifact = await _fixtureArtifact();
    final bytes = Uint8List.fromList(List<int>.generate(4096, (i) => i % 251));
    final adapter = _RecordingAdapter(
      (_) async => ResponseBody.fromBytes(
        bytes,
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['application/zip'],
        },
      ),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    final downloader = DioAppUpdateBinaryDownloader(dio: dio);
    final stagingPath =
        '${(await Directory.systemTemp.createTemp('y300-update-download-')).path}'
        '/${artifact.fileName}.part';
    addTearDown(() async {
      final parent = File(stagingPath).parent;
      if (await parent.exists()) {
        await parent.delete(recursive: true);
      }
    });

    final events = await downloader
        .download(artifact, stagingPath: stagingPath)
        .toList();

    expect(events.first.type, AppUpdateBinaryEventType.started);
    expect(events.last.type, AppUpdateBinaryEventType.completed);
    expect(events.last.receivedBytes, bytes.length);
    expect(events.last.progress, 1);
    expect(await File(stagingPath).readAsBytes(), bytes);
    expect(adapter.lastOptions?.responseType, ResponseType.stream);
    expect(
      adapter.lastOptions?.headers[Headers.acceptHeader],
      contains('application/vnd.android.package-archive'),
    );
  });

  test('coalesces concurrent downloads for the same artifact', () async {
    final artifact = await _fixtureArtifact();
    final response = Completer<ResponseBody>();
    final adapter = _RecordingAdapter((_) => response.future);
    final downloader = DioAppUpdateBinaryDownloader(
      dio: Dio()..httpClientAdapter = adapter,
    );
    final directory = await Directory.systemTemp.createTemp(
      'y300-update-single-flight-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/${artifact.fileName}.part';

    final first = downloader.download(artifact, stagingPath: path);
    final second = downloader.download(artifact, stagingPath: path);
    expect(identical(first, second), isTrue);
    await adapter.firstCall;
    response.complete(ResponseBody.fromBytes(<int>[1, 2, 3], 200));

    await Future.wait(<Future<List<AppUpdateBinaryEvent>>>[
      first.toList(),
      second.toList(),
    ]);
    expect(adapter.callCount, 1);
  });

  test('cancels and removes the partial staging file', () async {
    final artifact = await _fixtureArtifact();
    final adapter = _RecordingAdapter((options) async {
      final cancelFuture = options.cancelToken?.whenCancel;
      if (cancelFuture != null) {
        await cancelFuture;
      }
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.cancel,
      );
    });
    final downloader = DioAppUpdateBinaryDownloader(
      dio: Dio()..httpClientAdapter = adapter,
    );
    final directory = await Directory.systemTemp.createTemp(
      'y300-update-cancel-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/${artifact.fileName}.part';
    final eventsFuture = downloader
        .download(artifact, stagingPath: path)
        .toList();
    await adapter.firstCall;

    await downloader.cancel();
    final events = await eventsFuture;

    expect(events.last.type, AppUpdateBinaryEventType.cancelled);
    expect(
      events.last.failure?.code,
      AppUpdateFailureCode.apkDownloadCancelled,
    );
    expect(await File(path).exists(), isFalse);
  });

  test('can retry after a failed download', () async {
    final artifact = await _fixtureArtifact();
    late final _RecordingAdapter adapter;
    adapter = _RecordingAdapter((options) async {
      if (adapter.callCount == 1) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      }
      return ResponseBody.fromBytes(<int>[4, 5, 6], 200);
    });
    final downloader = DioAppUpdateBinaryDownloader(
      dio: Dio()..httpClientAdapter = adapter,
    );
    final directory = await Directory.systemTemp.createTemp(
      'y300-update-retry-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/${artifact.fileName}.part';

    final first = await downloader
        .download(artifact, stagingPath: path)
        .toList();
    final second = await downloader
        .download(artifact, stagingPath: path)
        .toList();

    expect(first.last.type, AppUpdateBinaryEventType.failed);
    expect(second.last.type, AppUpdateBinaryEventType.completed);
    expect(adapter.callCount, 2);
    expect(await File(path).readAsBytes(), <int>[4, 5, 6]);
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
