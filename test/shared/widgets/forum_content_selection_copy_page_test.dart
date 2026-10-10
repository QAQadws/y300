import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/clipboard/clipboard_text_writer.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_content_selection_copy_page.dart';

import '../../test_support/localized_test_app.dart';

const _bodyKey = ValueKey('selection-body-text');
const _forumUrl = 'https://bbs.yamibo.com/thread-123-2-1.html';

void main() {
  _testForPlatform(
    'default page retains the real long-press Copy menu and platform write',
    (tester) async {
      final writes = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') writes.add(call);
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await _pumpPage(tester, text: 'first second');

      await _selectWord(tester, 2);
      final region = _region(tester);
      final toolbar = _toolbar(tester);
      _expectDefaultItemsPreserved(region, toolbar);
      expect(
        toolbar.buttonItems,
        hasLength(region.contextMenuButtonItems.length),
      );
      expect(
        find.text(MaterialLocalizations.of(region.context).copyButtonLabel),
        findsOneWidget,
      );
      expect(_selectedText(tester), 'first');

      await tester.tap(
        find.text(MaterialLocalizations.of(region.context).copyButtonLabel),
      );
      await tester.pumpAndSettle();

      expect(writes, hasLength(1));
      expect(writes.single.arguments, {'text': 'first'});
      expect(_selectedText(tester), isEmpty);
      expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
    },
  );

  _testForPlatform(
    'custom menu preserves default item types, labels and order before localized Open',
    (tester) async {
      final writer = _ControlledWriter();
      await _pumpPage(
        tester,
        text: _forumUrl,
        writer: writer,
        resolver: (text) => text == _forumUrl ? text : null,
        open: (_, _) async {},
        locale: const Locale('en'),
      );
      await _selectAll(tester);

      final region = _region(tester);
      final toolbar = _toolbar(tester);
      final expected = region.contextMenuButtonItems;
      _expectDefaultItemsPreserved(region, toolbar);
      expect(toolbar.buttonItems, hasLength(expected.length + 1));
      expect(toolbar.buttonItems!.last.type, ContextMenuButtonType.custom);
      expect(
        toolbar.buttonItems!.last.label,
        AppLocalizations.of(region.context).selectionOpenForumLink,
      );
      expect(writer.writes, isEmpty);
    },
  );

  _testForPlatform(
    'Copy writes once while pending and clears Android selection only on success',
    (tester) async {
      final writer = _ControlledWriter();
      const text = '分享 😀 $_forumUrl\n';
      await _pumpPage(tester, text: text, writer: writer);
      await _selectAll(tester);
      final copy = _copyItem(tester);

      copy.onPressed!();
      copy.onPressed!();
      await tester.pump();
      expect(writer.writes, [text]);
      expect(_selectedText(tester), text);
      expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);

      writer.completions.single.complete();
      await tester.pumpAndSettle();
      expect(writer.writes, [text]);
      expect(_selectedText(tester), isEmpty);
      expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
    },
  );

  _testForPlatform(
    'failed Copy keeps its selection and menu available for one explicit retry',
    (tester) async {
      final writer = _ControlledWriter();
      await _pumpPage(tester, text: 'copy this exactly', writer: writer);
      await _selectAll(tester);
      _copyItem(tester).onPressed!();
      writer.completions.single.completeError(
        PlatformException(code: 'write_failed'),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(_selectedText(tester), 'copy this exactly');
      expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
      _copyItem(tester).onPressed!();
      expect(writer.writes, ['copy this exactly', 'copy this exactly']);
      writer.completions.last.complete();
      await tester.pumpAndSettle();
      expect(_selectedText(tester), isEmpty);
    },
  );

  _testForPlatform('old Copy completion cannot clear a newer user selection', (
    tester,
  ) async {
    final writer = _ControlledWriter();
    await _pumpPage(tester, text: 'first second', writer: writer);
    await _selectAll(tester);
    _copyItem(tester).onPressed!();
    _region(tester).clearSelection();
    await tester.pumpAndSettle();
    await _selectWord(tester, 8);
    expect(_selectedText(tester), 'second');

    writer.completions.single.complete();
    await tester.pumpAndSettle();
    expect(_selectedText(tester), 'second');
    expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
  });

  _testForPlatform('same text at a different position retires the old menu', (
    tester,
  ) async {
    final writer = _ControlledWriter();
    await _pumpPage(tester, text: 'same other same', writer: writer);
    await _selectWord(tester, 1);
    final oldCopy = _copyItem(tester);
    expect(_selectedText(tester), 'same');
    await _selectWord(tester, 12);
    expect(_selectedText(tester), 'same');
    oldCopy.onPressed!();
    expect(writer.writes, isEmpty);
    _copyItem(tester).onPressed!();
    expect(writer.writes, ['same']);
    writer.completions.single.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  _testForPlatform(
    'traditional Chinese menu fits a narrow dark large-text page',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(300, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        LocalizedTestApp(
          locale: const Locale('zh', 'TW'),
          theme: ThemeData.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: ForumContentSelectionCopyPage(
            title: 'Selection test',
            resolveForumLink: (text) => text == _forumUrl ? text : null,
            onOpenForumLink: (_, _) async {},
            child: const Text(_forumUrl, key: _bodyKey),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _selectAll(tester);
      final label = AppLocalizations.of(
        _region(tester).context,
      ).selectionOpenForumLink;
      if (find.text(label).evaluate().isEmpty) {
        await tester.tap(
          find.byTooltip(
            MaterialLocalizations.of(_region(tester).context).moreButtonTooltip,
          ),
        );
        await tester.pumpAndSettle();
      }
      expect(find.text(label), findsOneWidget);
      expect(find.bySemanticsLabel(label), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  _testForPlatform(
    'removed page rejects saved menu actions and ignores late Copy completion',
    (tester) async {
      final writer = _ControlledWriter();
      final opened = <String>[];
      await _pumpPage(
        tester,
        text: _forumUrl,
        writer: writer,
        resolver: (text) => text,
        open: (url, _) async => opened.add(url),
      );
      await _selectAll(tester);
      final copy = _copyItem(tester);
      final open = _toolbar(tester).buttonItems!.last;
      copy.onPressed!();
      await tester.pumpWidget(const LocalizedTestApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();

      copy.onPressed!();
      open.onPressed!();
      writer.completions.single.complete();
      await tester.pumpAndSettle();
      expect(writer.writes, [_forumUrl]);
      expect(opened, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  _testForPlatform(
    'Open clears selection first, commits once and retires its lease on new selection',
    (tester) async {
      final completion = Completer<void>();
      final opened = <String>[];
      bool Function()? lease;
      await _pumpPage(
        tester,
        text: _forumUrl,
        resolver: (text) => text == _forumUrl ? text : null,
        open: (url, isCurrent) {
          expect(_selectedText(tester), isEmpty);
          expect(isCurrent(), isTrue);
          opened.add(url);
          lease = isCurrent;
          return completion.future;
        },
      );
      await _selectAll(tester);
      final open = _toolbar(tester).buttonItems!.last;
      open.onPressed!();
      open.onPressed!();
      await tester.pumpAndSettle();

      expect(opened, [_forumUrl]);
      expect(lease!(), isTrue);
      expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
      await _selectAll(tester);
      expect(lease!(), isFalse);
      completion.complete();
      await tester.pumpAndSettle();
      expect(_selectedText(tester), _forumUrl);
    },
  );

  _testForPlatform(
    'saved Open rechecks current selection and local classification without navigation',
    (tester) async {
      final opened = <String>[];
      var eligible = true;
      await _pumpPage(
        tester,
        text: _forumUrl,
        resolver: (text) => eligible ? text : null,
        open: (url, _) async => opened.add(url),
      );
      await _selectAll(tester);
      final open = _toolbar(tester).buttonItems!.last;
      eligible = false;
      open.onPressed!();
      await tester.pump();
      expect(opened, isEmpty);
      expect(_selectedText(tester), _forumUrl);

      eligible = true;
      _region(tester).clearSelection();
      await tester.pumpAndSettle();
      await _selectAll(tester);
      open.onPressed!();
      await tester.pump();
      expect(opened, isEmpty);
      expect(_selectedText(tester), _forumUrl);
    },
  );

  _testForPlatform('source validity gates saved Copy and Open actions', (
    tester,
  ) async {
    var current = true;
    final writer = _ControlledWriter();
    final opened = <String>[];
    await _pumpPage(
      tester,
      text: _forumUrl,
      writer: writer,
      resolver: (text) => text,
      open: (url, _) async => opened.add(url),
      isCurrent: () => current,
    );
    await _selectAll(tester);
    final copy = _copyItem(tester);
    final open = _toolbar(tester).buttonItems!.last;
    current = false;
    copy.onPressed!();
    open.onPressed!();
    await tester.pump();
    expect(writer.writes, isEmpty);
    expect(opened, isEmpty);
    expect(_selectedText(tester), _forumUrl);
  });

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.windows,
    TargetPlatform.fuchsia,
  ]) {
    _testForPlatform(
      'successful Copy preserves ${platform.name} selection cleanup semantics',
      (tester) async {
        final writer = _ControlledWriter();
        await _pumpPage(tester, text: 'first second', writer: writer);
        await _selectAll(tester);
        _copyItem(tester).onPressed!();
        expect(_selectedText(tester), 'first second');
        writer.completions.single.complete();
        await tester.pumpAndSettle();

        expect(writer.writes, ['first second']);
        expect(
          _selectedText(tester),
          platform == TargetPlatform.fuchsia ? isEmpty : 'first second',
        );
        expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
        expect(tester.takeException(), isNull);
      },
      platform: platform,
    );
  }
}

void _testForPlatform(
  String description,
  WidgetTesterCallback body, {
  TargetPlatform platform = TargetPlatform.android,
}) =>
    testWidgets(description, body, variant: TargetPlatformVariant({platform}));

Future<void> _pumpPage(
  WidgetTester tester, {
  required String text,
  ClipboardTextWriter? writer,
  String? Function(String)? resolver,
  ForumSelectionLinkOpener? open,
  bool Function()? isCurrent,
  Locale locale = const Locale('zh'),
}) async {
  await tester.pumpWidget(
    LocalizedTestApp(
      locale: locale,
      home: ForumContentSelectionCopyPage(
        title: 'Selection test',
        clipboardTextWriter: writer,
        resolveForumLink: resolver,
        onOpenForumLink: open,
        isCurrent: isCurrent,
        child: Text(text, key: _bodyKey),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

SelectableRegionState _region(WidgetTester tester) =>
    tester.state<SelectableRegionState>(find.byType(SelectableRegion));

AdaptiveTextSelectionToolbar _toolbar(WidgetTester tester) =>
    tester.widget<AdaptiveTextSelectionToolbar>(
      find.byType(AdaptiveTextSelectionToolbar),
    );

ContextMenuButtonItem _copyItem(WidgetTester tester) => _toolbar(
  tester,
).buttonItems!.singleWhere((item) => item.type == ContextMenuButtonType.copy);

void _expectDefaultItemsPreserved(
  SelectableRegionState region,
  AdaptiveTextSelectionToolbar toolbar,
) {
  final defaults = region.contextMenuButtonItems;
  final actual = toolbar.buttonItems!.take(defaults.length).toList();
  expect(actual.map((item) => item.type), defaults.map((item) => item.type));
  expect(actual.map((item) => item.label), defaults.map((item) => item.label));
}

Future<void> _selectAll(WidgetTester tester) async {
  _region(tester).selectAll(SelectionChangedCause.toolbar);
  await tester.pumpAndSettle();
  expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
}

RenderParagraph _paragraph(WidgetTester tester) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byKey(_bodyKey),
        matching: find.byType(RichText),
      ),
    );

String _selectedText(WidgetTester tester) {
  final paragraph = _paragraph(tester);
  final text = paragraph.text.toPlainText();
  return paragraph.selections
      .map((selection) => text.substring(selection.start, selection.end))
      .join();
}

Future<void> _selectWord(WidgetTester tester, int offset) async {
  final paragraph = _paragraph(tester);
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: offset, extentOffset: offset + 1),
  );
  await tester.longPressAt(
    paragraph.localToGlobal(boxes.single.toRect().center),
  );
  await tester.pumpAndSettle();
  expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
}

class _ControlledWriter implements ClipboardTextWriter {
  final writes = <String>[];
  final completions = <Completer<void>>[];

  @override
  Future<void> writeText(String text) {
    writes.add(text);
    final completion = Completer<void>();
    completions.add(completion);
    return completion.future;
  }
}
