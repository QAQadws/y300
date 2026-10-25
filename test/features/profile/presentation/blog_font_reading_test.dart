import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/localization/app_server_content_conversion_provider.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/fonts/domain/repositories/font_library_repository.dart';
import 'package:y300/features/fonts/domain/services/font_runtime_loader.dart';
import 'package:y300/features/fonts/fonts.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter_factory.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../test_support/localized_test_app.dart';
import '../test_support/blog_detail_fixture.dart';
import '../test_support/blog_text_converter_fixture.dart';

const _first = ImportedFont(
  id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  displayName: 'First',
  storageFileName: 'first.ttf',
  byteLength: 1,
);
const _second = ImportedFont(
  id: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  displayName: 'Second',
  storageFileName: 'second.ttf',
  byteLength: 1,
);
const _articleSource = 'profile-blog-11';
const _commentSource = 'profile-blog-comment-31';

void main() {
  testWidgets(
    'blog body shares font settings while conversion and author CSS remain local',
    (tester) async {
      final host = _Host()..convert = true;
      host.preferences.value = host.preferences.value.copyWith(
        fontFamily: _first.id,
      );
      host.details.bodyHtml =
          '<p>正文</p>'
          '<p style="font-family: AuthorFont; font-weight:700"><i>Author emphasis</i></p>';
      host.details.commentHtml = '<p>评论</p>';
      await host.pump(tester);
      await _ready(
        tester,
        _articleSource,
        FontIdentity.runtimeFamily(_first.id),
      );
      await _ready(
        tester,
        _commentSource,
        FontIdentity.runtimeFamily(_first.id),
      );
      await _pumpUntil(
        tester,
        () => find.text('內文', findRichText: true).evaluate().isNotEmpty,
      );
      expect(find.text('評論', findRichText: true), findsOneWidget);
      expect(_styleForText(tester, 'Article 11').fontFamily, 'NativeUi');
      final authorStyle = _styleForText(tester, 'Author emphasis');
      expect(authorStyle.fontFamily, 'AuthorFont');
      expect(authorStyle.fontWeight, FontWeight.w700);
      expect(authorStyle.fontStyle, FontStyle.italic);

      final source = _renderer(tester, _articleSource).preparedDocument;
      final conversions = List<String>.of(host.converter.inputs);
      await host.controller.setFontFamily(_second.id);
      await _ready(
        tester,
        _articleSource,
        FontIdentity.runtimeFamily(_second.id),
      );
      await _ready(
        tester,
        _commentSource,
        FontIdentity.runtimeFamily(_second.id),
      );
      expect(_renderer(tester, _articleSource).preparedDocument, same(source));
      expect(host.converter.inputs, conversions);
      expect(host.preferences.value.conversionMode, TextConversionMode.none);

      final button = find.byKey(const Key('blog-detail-display-settings'));
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ProfileBlogDetailPage)),
      );
      expect(
        tester.widget<IconButton>(button).tooltip,
        l10n.threadHtmlConversionSettings,
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      final sheet = tester.widget<ForumHtmlReaderSettingsSheet>(
        find.byKey(const Key('blog-detail-display-settings-sheet')),
      );
      expect(sheet.showConversionControls, isFalse);
      expect(sheet.showAuthorStyleControls, isFalse);
      expect(
        find.byKey(const Key('forum-html-reader-font-family')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'blog cold load waits for the selected runtime font before rendering body',
    (tester) async {
      final host = _Host();
      host.preferences.value = host.preferences.value.copyWith(
        fontFamily: _first.id,
      );
      final fontReady = Completer<void>();
      host.runtime.gates[_first.id] = fontReady;
      await host.pump(tester, settle: false);
      await _pumpUntil(
        tester,
        () => host.runtime.requested.contains(_first.id),
      );
      expect(find.text('Article 11'), findsWidgets);
      expect(find.byType(ForumHtmlWidgetPostRenderer), findsNothing);
      fontReady.complete();
      await _ready(
        tester,
        _articleSource,
        FontIdentity.runtimeFamily(_first.id),
      );
      await _ready(
        tester,
        _commentSource,
        FontIdentity.runtimeFamily(_first.id),
      );
      expect(host.preferences.saved, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final comment in [false, true]) {
    testWidgets(
      '${comment ? 'comment' : 'article'} copy follows font changes and deletion across routes',
      (tester) async {
        final host = _Host();
        host.preferences.value = host.preferences.value.copyWith(
          fontFamily: _first.id,
          typography: host.preferences.value.typography.copyWith(
            fontScale: 1.4,
          ),
        );
        await host.pump(tester);
        final source = comment ? _commentSource : _articleSource;
        await _ready(tester, source, FontIdentity.runtimeFamily(_first.id));
        await _openCopyPage(tester, comment: comment);
        final page = find.byKey(const Key('blog-selection-copy-page'));
        await _ready(
          tester,
          source,
          FontIdentity.runtimeFamily(_first.id),
          within: page,
        );
        final body = find.descendant(
          of: page,
          matching: find.byKey(Key('forum-html-renderer-$source')),
        );
        final bodyElement = tester.element(body);
        final selection = find.descendant(
          of: page,
          matching: find.byType(SelectionArea),
        );
        final selectionElement = tester.element(selection);
        final document = _renderer(
          tester,
          source,
          within: page,
        ).preparedDocument;
        final fontReady = Completer<void>();
        host.runtime.gates[_second.id] = fontReady;
        final selected = host.controller.setFontFamily(_second.id);
        await _pumpUntil(
          tester,
          () => host.runtime.requested.contains(_second.id),
        );
        expect(
          _renderer(tester, source, within: page).textStyle!.fontFamily,
          FontIdentity.runtimeFamily(_first.id),
        );
        fontReady.complete();
        await selected;
        await _ready(
          tester,
          source,
          FontIdentity.runtimeFamily(_second.id),
          within: page,
        );
        await tester.runAsync(() => host.service.deleteFont(_second.id));
        await _ready(tester, source, null, within: page);
        expect(
          _renderer(tester, source, within: page).preparedDocument,
          same(document),
        );
        expect(tester.element(body), same(bodyElement));
        expect(tester.element(selection), same(selectionElement));
        expect(host.preferences.value.fontFamily, FontIdentity.system);
        expect(host.preferences.value.typography.fontScale, 1.4);

        Navigator.of(tester.element(page)).pop();
        await tester.pumpAndSettle();
        await _ready(tester, _articleSource, null);
        await _ready(tester, _commentSource, null);
        expect(host.details.queries, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }
}

ForumHtmlWidgetPostRenderer _renderer(
  WidgetTester tester,
  String source, {
  Finder? within,
}) {
  final body = find.byWidgetPredicate(
    (widget) =>
        widget is ForumHtmlWidgetPostRenderer && widget.sourceId == source,
  );
  return tester.widget(
    within == null ? body : find.descendant(of: within, matching: body),
  );
}

Future<void> _ready(
  WidgetTester tester,
  String source,
  String? family, {
  Finder? within,
}) async {
  await _pumpUntil(tester, () {
    final body = find.byWidgetPredicate(
      (widget) =>
          widget is ForumHtmlWidgetPostRenderer && widget.sourceId == source,
    );
    final matches = within == null
        ? body
        : find.descendant(of: within, matching: body);
    if (matches.evaluate().length != 1) return false;
    final expectedFamily =
        family ??
        Theme.of(tester.element(matches)).textTheme.bodyMedium?.fontFamily;
    return tester
            .widget<ForumHtmlWidgetPostRenderer>(matches)
            .textStyle
            ?.fontFamily ==
        expectedFamily;
  });
  await tester.pumpAndSettle();
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (var frame = 0; frame < 200; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (ready()) return;
  }
  fail('Blog body did not reach the requested font state');
}

Future<void> _openCopyPage(WidgetTester tester, {required bool comment}) async {
  final card = find.byKey(
    Key(comment ? 'profile-blog-comment-31' : 'blog-detail-card'),
  );
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
  await tester.longPressAt(tester.getTopLeft(card) + const Offset(20, 3));
  await tester.pumpAndSettle();
  final action = find.byKey(const Key('blog-content-action-select-copy'));
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pumpAndSettle();
}

TextStyle _styleForText(WidgetTester tester, String text) {
  TextStyle? matching(InlineSpan span, TextStyle inherited) {
    if (span is! TextSpan) return null;
    final style = inherited.merge(span.style);
    if (span.text?.contains(text) == true) return style;
    for (final child in span.children ?? const <InlineSpan>[]) {
      final found = matching(child, style);
      if (found != null) return found;
    }
    return null;
  }

  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    final found = matching(richText.text, const TextStyle());
    if (found != null) return found;
  }
  fail('No rendered style for $text');
}

final class _Host {
  final details = BlogDetailFixture();
  final preferences = _Preferences();
  final fonts = _Fonts();
  final runtime = _Runtime();
  final converter = BlogTextConverterFixture();
  bool convert = false;
  late final service = FontLibraryService(
    repository: fonts,
    runtimeLoader: runtime,
  );
  late final container = ProviderContainer(
    overrides: [
      blogAccountIdProvider.overrideWithValue('101'),
      userBlogDetailRepositoryProvider.overrideWithValue(details),
      imageCacheServiceProvider.overrideWithValue(_Images()),
      userBlogNavigationProvider.overrideWithValue(null),
      forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
      forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(
        preferences,
      ),
      fontLibraryServiceProvider.overrideWithValue(service),
      appServerContentConversionModeProvider.overrideWithValue(
        convert ? converter.mode : TextConversionMode.none,
      ),
      textConverterProvider(converter.mode).overrideWithValue(converter),
    ],
  );

  ForumHtmlReaderPreferencesController get controller =>
      container.read(forumHtmlReaderPreferencesControllerProvider.notifier);

  Future<void> pump(WidgetTester tester, {bool settle = true}) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      container.dispose();
      service.dispose();
      await fonts.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          theme: ThemeData(fontFamily: 'NativeUi'),
          home: const ProfileBlogDetailPage(ownerUserId: '202', blogId: '11'),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }
}

final class _Preferences implements ForumHtmlReaderPreferencesRepository {
  ForumHtmlReaderPreferences value = ForumHtmlReaderPreferences.defaults();
  final saved = <ForumHtmlReaderPreferences>[];
  @override
  Future<ForumHtmlReaderPreferences> load() async => value;
  @override
  Future<void> save(ForumHtmlReaderPreferences preferences) async {
    value = preferences;
    saved.add(preferences);
  }
}

final class _Fonts implements FontLibraryRepository {
  final entries = <String, ImportedFont>{
    _first.id: _first,
    _second.id: _second,
  };
  final _changes = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get changes => _changes.stream;
  @override
  Future<List<ImportedFont>> listFonts() async =>
      List.unmodifiable(entries.values);
  @override
  Future<Uint8List> readFont(String fontId) async {
    if (!entries.containsKey(fontId)) {
      throw const FontLibraryException(FontLibraryFailure.notFound);
    }
    return Uint8List(1);
  }

  @override
  Future<void> deleteFont(String fontId) async {
    entries.remove(fontId);
    _changes.add(null);
  }

  @override
  Future<void> dispose() => _changes.close();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected font repository call');
}

final class _Runtime implements FontRuntimeLoader {
  final gates = <String, Completer<void>>{};
  final requested = <String>[];
  @override
  Future<String> load(ImportedFont font, Uint8List bytes) async {
    requested.add(font.id);
    await gates[font.id]?.future;
    return FontIdentity.runtimeFamily(font.id);
  }
}

final class _Images implements ImageCacheService {
  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async =>
      const CachedImageResult(success: false);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
