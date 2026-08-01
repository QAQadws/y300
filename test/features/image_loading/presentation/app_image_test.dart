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
}

/// 永不完成的 header builder，用于确定性验证网络分支的“等待头部”态。
class _PendingImageHeaderBuilder implements ImageRequestHeaderBuilder {
  final Completer<Map<String, String>> _completer =
      Completer<Map<String, String>>();

  @override
  Future<Map<String, String>> buildHeaders(String imageUrl) =>
      _completer.future;
}
