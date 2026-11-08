import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/clipboard/clipboard_providers.dart';
import 'package:y300/features/thread/presentation/services/thread_post_actions.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

import '../../../../test_support/localized_test_app.dart';

void main() {
  for (final locale in [const Locale('zh'), const Locale('zh', 'TW')]) {
    for (final status in ['voting', 'readOnly', 'submitting']) {
      testWidgets(
        '$locale $status long press copies only the displayed option',
        (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            final harness = await _Harness.open(
              tester,
              locale: locale,
              status: status,
            );
            final option = find.byKey(const Key('thread-poll-option-1'));
            expect(
              tester
                  .getSemantics(option)
                  .getSemanticsData()
                  .hasAction(ui.SemanticsAction.longPress),
              isTrue,
            );
            if (status == 'voting') {
              await tester.tap(option);
              await tester.pump();
              expect(harness.toggles, 1);
            }
            await tester.longPress(option);
            await _settle(tester);
            final sheet = find.byKey(const Key('thread-post-action-sheet'));
            expect(sheet, findsOneWidget);
            final copy = find.byKey(
              const Key('thread-post-copy-poll-option-action'),
            );
            final firstTile = find
                .descendant(of: sheet, matching: find.byType(ListTile))
                .first;
            expect(
              tester.widget<ListTile>(firstTile).key,
              tester.widget<ListTile>(copy).key,
            );
            expect(
              find.text(harness.strings.threadPollCopyOptionText),
              findsOneWidget,
            );
            expect(
              find.byKey(const Key('thread-post-copy-all-action')),
              findsOneWidget,
            );
            expect(harness.writes, isEmpty);
            await tester.tap(copy);
            await _settle(tester);
            expect(harness.writes, [_displayedLabel]);
            expect(harness.toggles, status == 'voting' ? 1 : 0);
            expect(harness.submissions, 0);
            expect(
              find.text(
                harness.strings.threadDetailCopySuccess(
                  harness.strings.threadPollOptionText,
                ),
              ),
              findsOneWidget,
            );
            expect(
              harness.container
                  .read(clipboardSelfCopyFingerprintRegistryProvider)
                  .containsText(_displayedLabel),
              isTrue,
            );
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }

  testWidgets('ordinary area and an empty option keep only ordinary actions', (
    tester,
  ) async {
    final harness = await _Harness.open(tester, optionLabel: '');
    for (final target in [
      find.byKey(const Key('ordinary-area')),
      find.byKey(const Key('thread-poll-option-1')),
    ]) {
      await tester.longPress(target);
      await _settle(tester);
      expect(
        find.byKey(const Key('thread-post-copy-poll-option-action')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('thread-post-copy-all-action')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('thread-post-copy-all-action')));
      await _settle(tester);
    }
    expect(harness.writes, ['Displayed body', 'Displayed body']);
    expect(harness.toggles, 0);
  });

  testWidgets('retired source cannot copy after opening the sheet', (
    tester,
  ) async {
    final harness = await _Harness.open(tester);
    await tester.longPress(find.byKey(const Key('thread-poll-option-1')));
    await _settle(tester);
    harness.active = false;
    await tester.tap(
      find.byKey(const Key('thread-post-copy-poll-option-action')),
    );
    await _settle(tester);
    expect(harness.writes, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('failed write has localized feedback and no success evidence', (
    tester,
  ) async {
    final harness = await _Harness.open(tester, failCopy: true);
    await tester.longPress(find.byKey(const Key('thread-poll-option-1')));
    await _settle(tester);
    await tester.tap(
      find.byKey(const Key('thread-post-copy-poll-option-action')),
    );
    await _settle(tester);
    expect(harness.writes, [_displayedLabel]);
    expect(
      find.text(harness.strings.threadPollCopyOptionFailed),
      findsOneWidget,
    );
    expect(
      harness.container
          .read(clipboardSelfCopyFingerprintRegistryProvider)
          .containsText(_displayedLabel),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
}

const _displayedLabel = '完整顯示選項，包含換行\n下一行';

class _Harness {
  final container = ProviderContainer();
  final writes = <String>[];
  final selected = <String>{};
  var toggles = 0;
  var submissions = 0;
  var active = true;
  late AppLocalizations strings;

  static Future<_Harness> open(
    WidgetTester tester, {
    Locale locale = const Locale('zh'),
    String status = 'voting',
    String optionLabel = _displayedLabel,
    bool failCopy = false,
  }) async {
    final harness = _Harness();
    addTearDown(harness.container.dispose);
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        fail('Copy must not read back clipboard content');
      }
      if (call.method == 'Clipboard.setData') {
        harness.writes.add((call.arguments as Map)['text'] as String);
        if (failCopy) throw PlatformException(code: 'synthetic_failure');
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final post = ThreadPost(
      pid: '1',
      author: 'author',
      authorId: '1',
      message: '<p>Displayed body</p>',
      number: 1,
      isFirst: true,
      dateline: 'today',
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: LocalizedTestApp(
          locale: locale,
          home: Consumer(
            builder: (context, ref, _) {
              harness.strings = AppLocalizations.of(context);
              final actions = ThreadPostActions(
                context: context,
                ref: ref,
                target: const ThreadPostActionContext(
                  tid: '100',
                  fid: '33',
                  subject: 'Poll',
                  page: 1,
                  capabilities: null,
                ),
                isCurrent: () => harness.active,
                imageReferer: null,
              );
              Future<void> open([ThreadPollOption? option]) async {
                await actions.show(
                  sourcePost: post,
                  displayPost: post,
                  pollOption: option,
                );
              }

              return Scaffold(
                body: GestureDetector(
                  onLongPress: () => open(),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    children: [
                      const Text('Body', key: Key('ordinary-area')),
                      StatefulBuilder(
                        builder: (context, update) => ThreadPollCard(
                          poll: ThreadPoll(
                            isMultipleChoice: false,
                            canVote: status != 'readOnly',
                            summary: '',
                            options: [
                              ThreadPollOption(
                                id: '1',
                                label: optionLabel,
                                voteCount: 8,
                                percent: 25,
                              ),
                            ],
                          ),
                          selectedOptionIds: harness.selected,
                          isSubmitting: status == 'submitting',
                          commandAvailable: true,
                          hint: null,
                          palette: ThreadDetailNativePalette.resolve(
                            Theme.of(context),
                          ),
                          onLongPressOption: (option) => open(option),
                          onToggleOption: (option) => update(() {
                            harness.toggles++;
                            harness.selected.add(option.id);
                          }),
                          onSubmit: () => harness.submissions++,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await _settle(tester);
    return harness;
  }
}

// Submission keeps a spinner active; advance only finite sheet transitions.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}
