import 'dart:async';

import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/image_loading/domain/app_image_source.dart';
import 'package:y300/features/image_loading/presentation/app_image.dart';

void main() {
  Widget wrap(Widget child) {
    return ProviderScope(child: LocalizedTestApp(home: child));
  }

  testWidgets('shows placeholder when no local file and no network source', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const AppImage(
          fit: BoxFit.cover,
          placeholder: SizedBox(key: Key('placeholder')),
        ),
      ),
    );

    expect(find.byKey(const Key('placeholder')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('falls back to network branch when local file is absent', (
    tester,
  ) async {
    // 用永不完成的 header builder，让网络分支停在“等待头部”态，从而确定性地
    // 验证：本地缺失时控件确实进入了网络兜底分支（而非干等队列喂路径）。
    final pendingHeaders = _PendingImageHeaderBuilder();
    await tester.pumpWidget(
      wrap(
        AppImage(
          localPath: 'E:/synthetic/missing-cover.jpg',
          networkSource: NetworkAppImageSource(
            url: 'https://bbs.yamibo.com/data/attachment/cover.jpg',
            headerBuilder: pendingHeaders,
          ),
          fit: BoxFit.cover,
          placeholder: const SizedBox(key: Key('placeholder')),
        ),
      ),
    );
    await tester.pump();

    // 进入网络分支、头部未就绪 → 展示占位（FutureBuilder 等待中）。
    expect(find.byKey(const Key('placeholder')), findsOneWidget);
  });

  testWidgets('default avatar urls resolve to error placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        AppImage(
          networkSource: NetworkAppImageSource(
            url: 'https://bbs.yamibo.com/uc_server/data/avatar/noavatar.svg',
          ),
          fit: BoxFit.cover,
          placeholder: const SizedBox(key: Key('placeholder')),
          errorPlaceholder: const SizedBox(key: Key('error')),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('error')), findsOneWidget);
  });

  testWidgets('reuses resolved headers across equivalent parent rebuilds', (
    tester,
  ) async {
    final headers = _CountingImageHeaderBuilder();

    Widget buildImage() {
      return wrap(
        AppImage(
          key: const Key('stable-network-image'),
          networkSource: NetworkAppImageSource(
            url: 'https://bbs.yamibo.com/data/attachment/stable.jpg',
            headerBuilder: headers,
          ),
          fit: BoxFit.contain,
          placeholder: const SizedBox(key: Key('placeholder')),
          errorPlaceholder: const SizedBox(key: Key('error')),
        ),
      );
    }

    await tester.pumpWidget(buildImage());
    await tester.pump();

    expect(headers.callCount, 1);
    expect(
      find.descendant(
        of: find.byKey(const Key('stable-network-image')),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(buildImage());

    expect(headers.callCount, 1);
    expect(
      find.descendant(
        of: find.byKey(const Key('stable-network-image')),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
  });

  testWidgets('invalidates headers only when request identity changes', (
    tester,
  ) async {
    final firstBuilder = _PendingImageHeaderBuilder();
    final secondBuilder = _PendingImageHeaderBuilder();

    Widget buildImage(String url, ImageRequestHeaderBuilder builder) {
      return wrap(
        AppImage(
          key: const Key('changing-network-image'),
          networkSource: NetworkAppImageSource(
            url: url,
            headerBuilder: builder,
          ),
          fit: BoxFit.contain,
          placeholder: const SizedBox(key: Key('placeholder')),
        ),
      );
    }

    await tester.pumpWidget(
      buildImage('https://bbs.yamibo.com/data/attachment/a.jpg', firstBuilder),
    );
    expect(firstBuilder.callCount, 1);

    await tester.pumpWidget(
      buildImage('https://bbs.yamibo.com/data/attachment/a.jpg', firstBuilder),
    );
    expect(firstBuilder.callCount, 1);

    await tester.pumpWidget(
      buildImage('https://bbs.yamibo.com/data/attachment/b.jpg', firstBuilder),
    );
    expect(firstBuilder.callCount, 2);

    await tester.pumpWidget(
      buildImage('https://bbs.yamibo.com/data/attachment/b.jpg', secondBuilder),
    );
    expect(secondBuilder.callCount, 1);
  });

  testWidgets(
    'header failure does not issue an unauthenticated image request',
    (tester) async {
      final headers = _FailingImageHeaderBuilder();
      await tester.pumpWidget(
        wrap(
          AppImage(
            networkSource: NetworkAppImageSource(
              url: 'https://bbs.yamibo.com/data/attachment/protected.jpg',
              headerBuilder: headers,
            ),
            fit: BoxFit.contain,
            placeholder: const SizedBox(key: Key('placeholder')),
            errorPlaceholder: const SizedBox(key: Key('error')),
          ),
        ),
      );
      await tester.pump();

      expect(headers.callCount, 1);
      expect(find.byKey(const Key('error')), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    },
  );
}

/// 永不完成的 header builder，用于确定性验证网络分支的“等待头部”态。
class _PendingImageHeaderBuilder implements ImageRequestHeaderBuilder {
  final Completer<Map<String, String>> _completer =
      Completer<Map<String, String>>();
  int callCount = 0;

  @override
  Future<Map<String, String>> buildHeaders(String imageUrl) {
    callCount += 1;
    return _completer.future;
  }
}

class _CountingImageHeaderBuilder implements ImageRequestHeaderBuilder {
  int callCount = 0;

  @override
  Future<Map<String, String>> buildHeaders(String imageUrl) async {
    callCount += 1;
    return const <String, String>{'Referer': 'https://bbs.yamibo.com/'};
  }
}

class _FailingImageHeaderBuilder implements ImageRequestHeaderBuilder {
  int callCount = 0;

  @override
  Future<Map<String, String>> buildHeaders(String imageUrl) {
    callCount += 1;
    return Future<Map<String, String>>.error(
      StateError('synthetic header failure'),
    );
  }
}
