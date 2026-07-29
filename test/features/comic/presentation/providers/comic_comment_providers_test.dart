import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/localization/app_server_content_conversion_provider.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/comic/domain/services/comic_comment_loader.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_session_controller.dart';
import 'package:y300/features/comic/presentation/providers/comic_comment_providers.dart';
import 'package:y300/features/comic/presentation/widgets/comic_comment_tail_surface.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter_factory.dart';

final _testModeControllerProvider =
    AsyncNotifierProvider<_TestModeController, TextConversionMode>(
      _TestModeController.new,
    );

void main() {
  test('mode updates retain the comment session and tail identities', () async {
    final loader = _ProviderLoader();
    final container = ProviderContainer(
      overrides: [
        comicCommentLoaderProvider.overrideWithValue(loader),
        appServerContentConversionModeProvider.overrideWith((ref) {
          return ref.watch(_testModeControllerProvider).value ??
              TextConversionMode.none;
        }),
        textConverterProvider.overrideWith(
          (ref, mode) => _ProviderConverter(mode),
        ),
        plainTextBatchConversionServiceProvider.overrideWithValue(
          _ProviderPlainService(),
        ),
        htmlTextNodeConversionServiceProvider.overrideWithValue(
          _ProviderHtmlService(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(_testModeControllerProvider.future);

    const key = ComicCommentSessionKey(
      episodeId: 'episode-1',
      sourceTid: '573279',
    );
    final tailProvider = comicCommentTailSurfaceProvider(key);
    final subscription = container.listen<ComicCommentTailSurface>(
      tailProvider,
      (previous, next) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final sessionBefore = container.read(
      comicCommentSessionControllerProvider(key),
    );
    final tailBefore = subscription.read();

    await sessionBefore.load();
    container
        .read(_testModeControllerProvider.notifier)
        .setMode(TextConversionMode.toTraditional);
    await _drain();

    expect(loader.calls, 1);
    expect(
      identical(
        sessionBefore,
        container.read(comicCommentSessionControllerProvider(key)),
      ),
      isTrue,
    );
    expect(identical(tailBefore, subscription.read()), isTrue);
    expect(
      container
          .read(comicCommentContentProjectionControllerProvider(key))
          .projection
          ?.isConverted,
      isTrue,
    );
  });
}

final class _TestModeController extends AsyncNotifier<TextConversionMode> {
  @override
  Future<TextConversionMode> build() async => TextConversionMode.none;

  void setMode(TextConversionMode mode) {
    state = AsyncData<TextConversionMode>(mode);
  }
}

Future<void> _drain() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

final class _ProviderLoader implements ComicCommentLoader {
  int calls = 0;

  @override
  Future<ComicCommentLoadResult> loadAll({
    required String sourceTid,
    ComicCommentCancellationToken? cancellationToken,
  }) async {
    calls += 1;
    return const ComicCommentLoadResult(
      sourceTid: '573279',
      status: ComicCommentLoadStatus.success,
      items: <ComicCommentItem>[
        ComicCommentItem(
          pid: 'p2',
          authorId: '8',
          authorName: '用户名',
          dateline: '软件时间',
          floorNumber: 2,
          rawMessage: '<p>软件正文</p>',
          avatarUrl: null,
        ),
      ],
      loadedPages: <int>{1},
      expectedPages: 1,
    );
  }
}

final class _ProviderPlainService implements PlainTextBatchConversionService {
  @override
  Future<List<String>> convertAll({
    required List<String> sources,
    required TextConverter converter,
  }) async {
    return <String>[for (final source in sources) 'T:$source'];
  }
}

final class _ProviderHtmlService extends HtmlTextNodeConversionService {
  @override
  Future<List<HtmlTextNodeConversionResult>> convertAll({
    required List<String> htmlFragments,
    required TextConverter converter,
    HtmlTextNodeConversionOptions options =
        const HtmlTextNodeConversionOptions(),
  }) async {
    return <HtmlTextNodeConversionResult>[
      for (final html in htmlFragments)
        HtmlTextNodeConversionResult(
          html: 'T:$html',
          convertedTextNodeCount: 1,
          converterId: converter.id,
        ),
    ];
  }
}

final class _ProviderConverter implements TextConverter {
  const _ProviderConverter(this.mode);

  @override
  final TextConversionMode mode;

  @override
  String get id => 'provider:${mode.name}';

  @override
  Future<String> convertHtml(String html) async => html;
}
