import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/clipboard/clipboard_providers.dart';
import 'package:y300/core/clipboard/clipboard_text_writer.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_post_html_selection_copy_page.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_content_selection_copy_page.dart';

import '../../../../test_support/localized_test_app.dart';

void main() {
  const url = 'https://bbs.yamibo.com/thread-123-2-1.html';

  testWidgets('thread selection opens one forum URL from share text', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    container
        .read(clipboardSelfCopyFingerprintRegistryProvider)
        .recordSuccessfulWrite(url);
    final calls = <String>[];
    bool Function()? lease;
    await tester.pumpWidget(
      _host(
        container,
        _page(
          '<p>分享：$url。</p>',
          onOpen: (value, isCurrent) async {
            calls.add(value);
            lease = isCurrent;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _selectAll(tester);
    final label = _openLabel(tester);
    expect(find.text(label), findsOneWidget);
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    expect(calls, [url]);
    expect(lease?.call(), isTrue);
    expect(find.text(label), findsNothing);
    expect(
      _region(tester).contextMenuButtonItems.where(
        (item) => item.type == ContextMenuButtonType.copy,
      ),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('thread selection keeps normal copy without an open callback', (
    tester,
  ) async {
    final writer = _Writer();
    final container = _container(writer: writer);
    addTearDown(container.dispose);
    await tester.pumpWidget(_host(container, _page('<p>$url</p>')));
    await tester.pumpAndSettle();
    await _selectAll(tester);
    expect(find.text(_openLabel(tester)), findsNothing);
    final copy = MaterialLocalizations.of(
      tester.element(find.byType(SelectionArea)),
    ).copyButtonLabel;
    expect(find.text(copy), findsOneWidget);
    await tester.tap(find.text(copy));
    await tester.pumpAndSettle();
    expect(writer.writes, [url]);
    expect(tester.takeException(), isNull);
  });

  for (final entry in <String, String>{
    'external URL': 'https://example.com/thread-123-2-1.html',
    'forum plus external': '$url https://example.com/',
    'two identical URLs': '$url $url',
    'two forum URLs': '$url https://bbs.yamibo.com/forum-42-1.html',
    'fake host': 'https://bbs.yamibo.com.example.com/thread-123-2-1.html',
    'action URL': '$url?action=delete',
    'incomplete URL': 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=',
  }.entries) {
    testWidgets('thread selection has no forum action for ${entry.key}', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);
      final calls = <String>[];
      await tester.pumpWidget(
        _host(
          container,
          _page(
            '<p>${const HtmlEscape().convert(entry.value)}</p>',
            onOpen: (value, _) async => calls.add(value),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _selectAll(tester);
      expect(find.text(_openLabel(tester)), findsNothing);
      expect(
        find.text(
          MaterialLocalizations.of(
            tester.element(find.byType(SelectionArea)),
          ).copyButtonLabel,
        ),
        findsOneWidget,
      );
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a complete URL split across inline styles remains selectable', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    final calls = <String>[];
    await tester.pumpWidget(
      _host(
        container,
        _page(
          '<p>分享：<span style="color:#005522">https://bbs.yamibo.com/</span>'
          '<b>thread-123-2-1.html</b>。</p>',
          onOpen: (value, _) async => calls.add(value),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _selectAll(tester);
    expect(find.text(_openLabel(tester)), findsOneWidget);
    await tester.tap(find.text(_openLabel(tester)));
    await tester.pumpAndSettle();
    expect(calls, [url]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a parseable selected prefix of the source URL has no action', (
    tester,
  ) async {
    final writer = _Writer();
    final container = _container(writer: writer);
    addTearDown(container.dispose);
    const full = '$url?authorid=101#pid456';
    await tester.pumpWidget(
      _host(
        container,
        _page('<p>$full</p>', onOpen: (_, _) async {}),
        platform: TargetPlatform.windows,
      ),
    );
    await tester.pumpAndSettle();
    await _selectTextPrefix(tester, full, url.length);
    expect(find.text(_openLabel(tester)), findsNothing);
    final copy = MaterialLocalizations.of(
      tester.element(find.byType(SelectionArea)),
    ).copyButtonLabel;
    expect(find.text(copy), findsOneWidget);
    await tester.tap(find.text(copy));
    await tester.pumpAndSettle();
    expect(writer.writes, [url]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing the body retires a pending selected-link lease', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    final pending = Completer<void>();
    bool Function()? lease;
    Future<void> open(String _, bool Function() isCurrent) {
      lease = isCurrent;
      return pending.future;
    }

    var html = '<p>$url</p>';
    Widget build() => _host(container, _page(html, onOpen: open));
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    await _selectAll(tester);
    await tester.tap(find.text(_openLabel(tester)));
    await tester.pumpAndSettle();
    expect(lease?.call(), isTrue);
    html = '<p>Changed body</p>';
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(lease?.call(), isFalse);
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection opener receives the source-page validity guard', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    var current = true;
    bool Function()? lease;
    await tester.pumpWidget(
      _host(
        container,
        _page(
          '<p>$url</p>',
          onOpen: (_, isCurrent) async => lease = isCurrent,
          isCurrent: () => current,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _selectAll(tester);
    await tester.tap(find.text(_openLabel(tester)));
    await tester.pumpAndSettle();
    expect(lease?.call(), isTrue);
    current = false;
    expect(lease?.call(), isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(lease?.call(), isFalse);
    expect(tester.takeException(), isNull);
  });
}

ProviderContainer _container({ClipboardTextWriter? writer}) =>
    ProviderContainer(
      overrides: [
        forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(
          _PreferencesRepository(),
        ),
        clipboardTextWriterProvider.overrideWithValue(writer ?? _Writer()),
      ],
    );

Widget _host(
  ProviderContainer container,
  Widget page, {
  TargetPlatform platform = TargetPlatform.android,
}) => UncontrolledProviderScope(
  container: container,
  child: LocalizedTestApp(
    theme: ThemeData(platform: platform),
    home: page,
  ),
);

ThreadPostHtmlSelectionCopyPage _page(
  String html, {
  ForumSelectionLinkOpener? onOpen,
  bool Function()? isCurrent,
}) => ThreadPostHtmlSelectionCopyPage(
  key: const ValueKey('selection-fixture'),
  post: ThreadPost(
    pid: 'p1',
    author: 'Author',
    authorId: '',
    message: html,
    number: 1,
    isFirst: false,
    dateline: 'date',
  ),
  threadId: '100',
  imageReferer: '',
  onOpenPostLink: (_) {},
  onOpenPostImage: null,
  onImageFallback: (_, _) {},
  onOpenSelectedPostLink: onOpen,
  isCurrent: isCurrent,
);

SelectableRegionState _region(WidgetTester tester) => tester
    .state<SelectionAreaState>(find.byType(SelectionArea))
    .selectableRegion;

String _openLabel(WidgetTester tester) => AppLocalizations.of(
  tester.element(find.byType(SelectionArea)),
).selectionOpenForumLink;

Future<void> _selectAll(WidgetTester tester) async {
  _region(tester).selectAll(SelectionChangedCause.toolbar);
  await tester.pumpAndSettle();
}

Future<void> _selectTextPrefix(
  WidgetTester tester,
  String text,
  int end,
) async {
  final finder = find
      .byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().contains(text),
      )
      .first;
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final startOffset = paragraph.text.toPlainText().indexOf(text);
  final startBox = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: startOffset, extentOffset: startOffset + 1),
      )
      .first;
  final endBox = paragraph
      .getBoxesForSelection(
        TextSelection(
          baseOffset: startOffset + end - 1,
          extentOffset: startOffset + end,
        ),
      )
      .last;
  final gesture = await tester.startGesture(
    paragraph.localToGlobal(Offset(startBox.left, startBox.toRect().center.dy)),
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveTo(
    paragraph.localToGlobal(Offset(endBox.right, endBox.toRect().center.dy)),
  );
  await gesture.up();
  await tester.pumpAndSettle();
  final point = paragraph.localToGlobal(endBox.toRect().center);
  final menuGesture = await tester.startGesture(
    point,
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await menuGesture.up();
  await tester.pumpAndSettle();
}

class _PreferencesRepository implements ForumHtmlReaderPreferencesRepository {
  @override
  Future<ForumHtmlReaderPreferences> load() async =>
      ForumHtmlReaderPreferences.defaults();

  @override
  Future<void> save(ForumHtmlReaderPreferences preferences) async {}
}

class _Writer implements ClipboardTextWriter {
  final writes = <String>[];

  @override
  Future<void> writeText(String text) async => writes.add(text);
}
