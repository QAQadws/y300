import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/features/thread/domain/models/thread_ui_feedback.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../../test_support/localized_test_app.dart';

// Screenshot exports opt in; regression runs do not depend on local fonts.
const _output = String.fromEnvironment('POLL_VISUAL_OUTPUT');
const _font = String.fromEnvironment('POLL_VISUAL_FONT');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (_font.isEmpty) return;
    final data = ByteData.sublistView(await File(_font).readAsBytes());
    for (final family in ['Ahem', 'Roboto']) {
      await (FontLoader(family)..addFont(Future.value(data))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets(
      '${locale.toLanguageTag()} selections require explicit voting',
      (tester) async {
        final harness = await _Harness.open(tester, locale: locale);
        final submit = find.byKey(const Key('thread-poll-submit-button'));
        expect(tester.widget<FilledButton>(submit).onPressed, isNull);
        expect(find.text(harness.strings.threadPollSelectOption), findsNothing);
        expect(find.text(harness.poll.summary), findsNothing);
        expect(find.text(harness.poll.rulesText!), findsOneWidget);
        final participants = find.byKey(const Key('thread-poll-participants'));
        expect(
          find.text(harness.strings.threadPollParticipants(101)),
          findsOneWidget,
        );
        expect(
          tester.getRect(participants).center.dy,
          closeTo(
            tester.getRect(find.byIcon(Icons.bar_chart_rounded)).center.dy,
            1,
          ),
        );
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(
          tester.getSize(submit).width,
          lessThan(tester.getSize(find.byType(ThreadPollCard)).width / 2),
        );
        expect(tester.getSize(submit).height, greaterThanOrEqualTo(48));
        final expandedHeight = tester
            .getSize(find.byType(ThreadPollCard))
            .height;
        await harness.capture('idle-${locale.toLanguageTag()}');

        await tester.tap(find.byKey(const Key('thread-poll-option-1')));
        await tester.pump();
        expect(harness.submissions, 0);
        expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
        expect(
          find.text(harness.strings.threadPollSelectedCount(1)),
          findsNothing,
        );
        expect(find.byType(LinearProgressIndicator), findsNothing);
        await harness.capture('selected-${locale.toLanguageTag()}');
        await tester.tap(submit);
        expect(harness.submissions, 1);

        await tester.tap(find.byKey(const Key('thread-poll-header')));
        await tester.pump();
        expect(submit, findsNothing);
        expect(find.text(_options.first.label), findsNothing);
        expect(find.byKey(const Key('thread-poll-rules')), findsNothing);
        expect(find.text(harness.poll.deadlineText!), findsNothing);
        expect(participants, findsOneWidget);
        expect(find.byIcon(Icons.expand_more), findsOneWidget);
        expect(
          tester.getSize(find.byType(ThreadPollCard)).height,
          lessThan(expandedHeight / 2),
        );
        expect(
          tester.getSize(find.byKey(const Key('thread-poll-header'))).height,
          greaterThanOrEqualTo(44),
        );
        await harness.capture('collapsed-${locale.toLanguageTag()}');
        await tester.tap(find.byKey(const Key('thread-poll-header')));
        await tester.pump();
        expect(find.text(harness.poll.rulesText!), findsOneWidget);
        expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
        expect(harness.selected, {'1'});
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('short poll options are compact and keep usable tap targets', (
    tester,
  ) async {
    final harness = await _Harness.open(
      tester,
      poll: const ThreadPoll(
        isMultipleChoice: false,
        summary: '单选投票，投票后结果可见，共有 985 人参与投票',
        rulesText: '单选投票，投票后结果可见',
        participantCount: 985,
        deadlineText: '距结束还有：117 天 15 小时 33 分钟',
        options: [
          ThreadPollOption(id: '1', label: '恋爱，超紧张的'),
          ThreadPollOption(id: '2', label: '出柜，超害怕的'),
          ThreadPollOption(id: '3', label: '都是地狱级别的'),
          ThreadPollOption(id: '4', label: '姐都不怕'),
        ],
      ),
    );
    Rect? previous;
    for (final option in harness.poll.options) {
      final row = tester.getRect(
        find.byKey(Key('thread-poll-option-${option.id}')),
      );
      expect(row.height, inInclusiveRange(36, 40));
      if (previous != null) {
        expect(row.top - previous.bottom, lessThanOrEqualTo(2));
      }
      previous = row;
    }
    expect(tester.takeException(), isNull);
    await harness.capture('compact-four-options');
    await tester.tap(find.byKey(const Key('thread-poll-header')));
    await tester.pump();
    expect(
      tester.getSize(find.byType(ThreadPollCard)).height,
      lessThanOrEqualTo(64),
    );
    await harness.capture('compact-collapsed');
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('heading stays in place when toggling at text scale $scale', (
      tester,
    ) async {
      final harness = await _Harness.open(
        tester,
        poll: _shortPoll,
        width: scale == 1 ? 390 : 240,
        textScale: scale,
      );
      final header = find.byKey(const Key('thread-poll-header'));
      final elements = [
        header,
        find.descendant(
          of: header,
          matching: find.text(harness.strings.threadPollVote),
        ),
        find.byKey(const Key('thread-poll-participants')),
        find.byIcon(Icons.bar_chart_rounded),
      ];
      final expandedRects = elements.map(tester.getRect).toList();
      expect(find.byKey(const Key('thread-poll-rules')), findsOneWidget);
      await harness.capture('stable-heading-expanded-$scale');
      await tester.tap(header);
      await tester.pump();
      for (var i = 0; i < elements.length; i++) {
        expect(tester.getRect(elements[i]), expandedRects[i]);
      }
      expect(find.byKey(const Key('thread-poll-rules')), findsNothing);
      expect(tester.takeException(), isNull);
      await harness.capture('stable-heading-collapsed-$scale');
      await tester.tap(header);
      await tester.pump();
      for (var i = 0; i < elements.length; i++) {
        expect(tester.getRect(elements[i]), expandedRects[i]);
      }
      expect(find.byKey(const Key('thread-poll-rules')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('collapsed heading centers within compact visual feedback', (
    tester,
  ) async {
    final harness = await _Harness.open(tester, poll: _shortPoll);
    final header = find.byKey(const Key('thread-poll-header'));
    await tester.tap(header);
    await tester.pump();
    final painted = tester.getRect(
      find.descendant(
        of: header,
        matching: find.byType(InkWell),
        matchRoot: true,
      ),
    );
    expect(painted.height, lessThanOrEqualTo(36));
    expect(tester.getSize(header).height, greaterThanOrEqualTo(44));
    final title = find.descendant(
      of: header,
      matching: find.text(harness.strings.threadPollVote),
    );
    expect(tester.getRect(title).center.dy, closeTo(painted.center.dy, 0.5));
    expect(
      tester
          .getRect(find.byKey(const Key('thread-poll-participants')))
          .center
          .dy,
      closeTo(painted.center.dy, 0.5),
    );
    await harness.capture('header-collapsed-aligned');
  });

  testWidgets('short selected options center within compact visual feedback', (
    tester,
  ) async {
    final harness = await _Harness.open(tester, poll: _shortPoll);
    final choice = find.byKey(const Key('thread-poll-option-1'));
    await tester.tap(choice);
    await tester.pump();
    final painted = tester.getRect(
      find.descendant(
        of: choice,
        matching: find.byType(InkWell),
        matchRoot: true,
      ),
    );
    expect(painted.height, lessThanOrEqualTo(36));
    expect(tester.getSize(choice).height, inInclusiveRange(36, 40));
    expect(
      tester.getRect(find.text(_shortPoll.options.first.label)).center.dy,
      closeTo(painted.center.dy, 0.5),
    );
    expect(
      tester.getRect(find.byIcon(Icons.check_box)).center.dy,
      closeTo(painted.center.dy, 0.5),
    );
    expect(harness.selected, {'1'});
    final target = tester.getRect(choice);
    await tester.tapAt(Offset(target.center.dx, target.bottom - 1));
    await tester.pump();
    expect(harness.selected, isEmpty);
    await tester.tapAt(Offset(target.center.dx, target.top + 1));
    await tester.pump();
    expect(harness.selected, {'1'});
    await harness.capture('short-selected-aligned');
  });

  testWidgets('multi-choice feedback follows selections and removals', (
    tester,
  ) async {
    final harness = await _Harness.open(tester, poll: _poll(multiple: true));
    expect(find.text(harness.strings.threadPollSelectOption), findsNothing);
    await tester.tap(find.byKey(const Key('thread-poll-option-1')));
    await tester.tap(find.byKey(const Key('thread-poll-option-2')));
    await tester.pump();
    expect(find.byIcon(Icons.check_box), findsNWidgets(2));
    expect(
      find.text(harness.strings.threadPollSelectedCount(2)),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('thread-poll-option-1')));
    await tester.pump();
    expect(find.byIcon(Icons.check_box), findsOneWidget);
    expect(
      find.text(harness.strings.threadPollSelectedCount(1)),
      findsOneWidget,
    );
    expect(harness.submissions, 0);
  });

  testWidgets(
    'unknown participation preserves source summary without guessing',
    (tester) async {
      const poll = ThreadPoll(
        isMultipleChoice: false,
        summary: '单选投票，共有 9 人参与投票',
        options: _options,
      );
      final harness = await _Harness.open(tester, poll: poll);
      expect(find.text(poll.summary), findsOneWidget);
      expect(find.byKey(const Key('thread-poll-participants')), findsNothing);
      expect(find.text(harness.strings.threadPollSelectOption), findsNothing);
      final card = tester.getRect(find.byType(ThreadPollCard));
      final action = tester.getRect(
        find.byKey(const Key('thread-poll-submit-button')),
      );
      expect(action.right, closeTo(card.right - 14, 0.1));
    },
  );

  testWidgets('zero participants and an empty rules field remain explicit', (
    tester,
  ) async {
    final harness = await _Harness.open(
      tester,
      poll: const ThreadPoll(
        isMultipleChoice: false,
        participantCount: 0,
        rulesText: '',
        summary: '共有 0 人参与投票',
        options: _options,
      ),
    );
    expect(
      find.text(harness.strings.threadPollParticipants(0)),
      findsOneWidget,
    );
    expect(find.text(harness.poll.summary), findsNothing);
    expect(find.byKey(const Key('thread-poll-rules')), findsNothing);
  });

  testWidgets('pending and unsupported commands cannot submit', (tester) async {
    final harness = await _Harness.open(tester);
    harness.update(() {
      harness.selected.add('1');
      harness.commandAvailable = false;
    });
    await tester.pump();
    final submit = find.byKey(const Key('thread-poll-submit-button'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    harness.update(() {
      harness.commandAvailable = true;
      harness.submitting = true;
    });
    await tester.pump();
    expect(find.text(harness.strings.threadPollSubmitting), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.tap(submit);
    await tester.tap(find.byKey(const Key('thread-poll-option-2')));
    await tester.pump();
    expect(harness.submissions, 0);
    expect(harness.selected, {'1'});
    await harness.capture('submitting');
  });

  testWidgets('accessibility exposes selected, disabled, and expanded states', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final harness = await _Harness.open(tester);
      final choice = find.byKey(const Key('thread-poll-option-1'));
      final header = find.byKey(const Key('thread-poll-header'));
      await tester.tap(choice);
      await tester.pump();
      var flags = tester
          .getSemantics(choice)
          .getSemanticsData()
          .flagsCollection;
      expect(flags.isChecked, ui.CheckedState.isTrue);
      expect(flags.isInMutuallyExclusiveGroup, isTrue);
      harness.update(() => harness.submitting = true);
      await tester.pump();
      flags = tester.getSemantics(choice).getSemanticsData().flagsCollection;
      expect(flags.isEnabled, ui.Tristate.isFalse);
      expect(
        tester
            .getSemantics(header)
            .getSemanticsData()
            .flagsCollection
            .isExpanded,
        ui.Tristate.isTrue,
      );
      await tester.tap(header);
      await tester.pump();
      expect(
        tester
            .getSemantics(header)
            .getSemanticsData()
            .flagsCollection
            .isExpanded,
        ui.Tristate.isFalse,
      );
    } finally {
      semantics.dispose();
    }
  });

  for (final results in [false, true]) {
    testWidgets('read-only polls preserve source result visibility $results', (
      tester,
    ) async {
      final harness = await _Harness.open(
        tester,
        poll: _poll(readOnly: true, results: results),
      );
      expect(find.byKey(const Key('thread-poll-submit-button')), findsNothing);
      expect(find.text(harness.poll.statusText!), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
      expect(
        find.byType(LinearProgressIndicator),
        results ? findsNWidgets(3) : findsNothing,
      );
      expect(
        find.text(harness.strings.threadPollVotes(62)),
        results ? findsOneWidget : findsNothing,
      );
      if (results) expect(find.text('61.39%'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('thread-poll-option-1')),
        warnIfMissed: false,
      );
      expect(harness.selected, isEmpty);
      await harness.capture(results ? 'results' : 'closed-hidden');
      await tester.tap(find.byKey(const Key('thread-poll-header')));
      await tester.pump();
      expect(find.text(harness.poll.statusText!), findsNothing);
      expect(find.text(harness.poll.deadlineText!), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byKey(const Key('thread-poll-rules')), findsNothing);
      expect(find.byKey(const Key('thread-poll-participants')), findsOneWidget);
    });
  }

  testWidgets('unknown outcomes use localized feedback without auto-submit', (
    tester,
  ) async {
    final harness = await _Harness.open(tester);
    harness.update(() {
      harness.hint = '<xml>private diagnostic payload</xml>';
      harness.notice = const ThreadActionNotice(
        code: ThreadActionNoticeCode.unknown,
        action: ThreadActionKind.vote,
      );
    });
    await tester.pump();
    expect(
      find.text(harness.strings.threadPollVoteOutcomeUnknown),
      findsOneWidget,
    );
    expect(find.text(harness.hint!), findsNothing);
    expect(harness.submissions, 0);
  });

  for (final family in AppThemeFamily.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        '${family.name} ${brightness.name} handles narrow large text',
        (tester) async {
          final harness = await _Harness.open(
            tester,
            theme: AppTheme.build(family: family, brightness: brightness),
            width: 320,
            textScale: 2,
          );
          final submit = find.byKey(const Key('thread-poll-submit-button'));
          final card = tester.getRect(find.byType(ThreadPollCard));
          final action = tester.getRect(submit);
          final participants = tester.getRect(
            find.byKey(const Key('thread-poll-participants')),
          );
          expect(participants.left, greaterThanOrEqualTo(card.left));
          expect(participants.right, lessThanOrEqualTo(card.right));
          expect(action.width, lessThan(card.width));
          expect(action.right, lessThanOrEqualTo(card.right));
          expect(submit.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await harness.capture('${family.name}-${brightness.name}-narrow');

          harness.update(() => harness.submitting = true);
          await tester.pump();
          expect(tester.takeException(), isNull);
          await harness.capture('${family.name}-${brightness.name}-pending');
          harness.update(() {
            harness.submitting = false;
            harness.poll = _poll(readOnly: true, results: true);
          });
          await tester.pump();
          expect(
            find.text(harness.strings.threadPollVotes(62)),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await harness.capture('${family.name}-${brightness.name}-results');
        },
      );
    }
  }

  testWidgets('bad chart values stay readable and use the native fallback', (
    tester,
  ) async {
    final harness = await _Harness.open(
      tester,
      poll: const ThreadPoll(
        isMultipleChoice: false,
        canVote: false,
        summary: 'source summary',
        options: [
          ThreadPollOption(
            id: '1',
            label: 'invalid chart color',
            percent: 80,
            colorHex: '#badhex',
          ),
          ThreadPollOption(
            id: '2',
            label: 'votes without a finite percentage',
            voteCount: 3,
            percent: double.nan,
          ),
        ],
      ),
    );
    expect(find.text(harness.strings.threadPollVotes(3)), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.valueColor?.value, harness.palette.accent);
    expect(tester.takeException(), isNull);
  });
}

const _shortPoll = ThreadPoll(
  isMultipleChoice: true,
  maxChoices: 2,
  summary: '多选投票（最多可选 2 项），共有 260 人参与投票',
  rulesText: '多选投票（最多可选 2 项）',
  participantCount: 260,
  options: [
    ThreadPollOption(id: '1', label: '母女'),
    ThreadPollOption(id: '2', label: '姐妹'),
    ThreadPollOption(id: '3', label: '其他'),
  ],
);

const _options = [
  ThreadPollOption(id: '1', label: '长期来说应该学习技能与知识'),
  ThreadPollOption(id: '2', label: '人生苦短，及时享乐，没准嗝了'),
  ThreadPollOption(id: '3', label: '被生活推着学习，偷着享乐'),
];

ThreadPoll _poll({
  bool multiple = false,
  bool readOnly = false,
  bool results = false,
}) => ThreadPoll(
  isMultipleChoice: multiple,
  canVote: !readOnly,
  maxChoices: multiple ? 2 : null,
  summary: multiple
      ? '多选投票（最多可选 2 项），共有 101 人参与投票'
      : '单选投票，投票后结果可见，共有 101 人参与投票',
  participantCount: 101,
  rulesText: multiple ? '多选投票（最多可选 2 项）' : '单选投票，投票后结果可见',
  deadlineText: '距结束还有：296 天 4 小时 58 分钟',
  statusText: readOnly ? (results ? '您已经投过票，谢谢您的参与' : '投票已结束') : null,
  options: results
      ? [
          for (var i = 0; i < _options.length; i++)
            ThreadPollOption(
              id: _options[i].id,
              label: _options[i].label,
              voteCount: [62, 14, 25][i],
              percent: [61.39, 13.86, 24.75][i],
            ),
        ]
      : _options,
);

class _Harness {
  _Harness(this.tester, this.theme, this.poll);

  final WidgetTester tester;
  final ThemeData theme;
  ThreadPoll poll;
  final selected = <String>{};
  final boundary = GlobalKey();
  late StateSetter update;
  var submitting = false;
  var commandAvailable = true;
  var submissions = 0;
  String? hint;
  ThreadActionNotice? notice;

  ThreadDetailNativePalette get palette =>
      ThreadDetailNativePalette.resolve(theme);
  AppLocalizations get strings =>
      AppLocalizations.of(tester.element(find.byType(ThreadPollCard)));

  static Future<_Harness> open(
    WidgetTester tester, {
    ThemeData? theme,
    ThreadPoll? poll,
    Locale locale = const Locale('zh'),
    double width = 390,
    double textScale = 1,
  }) async {
    final harness = _Harness(
      tester,
      theme ?? AppTheme.light(),
      poll ?? _poll(),
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1200);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      LocalizedTestApp(
        theme: harness.theme,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: RepaintBoundary(
              key: harness.boundary,
              child: Material(
                color: harness.palette.card,
                child: StatefulBuilder(
                  builder: (context, update) {
                    harness.update = update;
                    return ThreadPollCard(
                      poll: harness.poll,
                      selectedOptionIds: harness.selected,
                      isSubmitting: harness.submitting,
                      commandAvailable: harness.commandAvailable,
                      hint: harness.hint,
                      notice: harness.notice,
                      palette: harness.palette,
                      onToggleOption: (option) => update(() {
                        if (!harness.poll.isMultipleChoice) {
                          harness.selected
                            ..clear()
                            ..add(option.id);
                        } else if (!harness.selected.remove(option.id)) {
                          harness.selected.add(option.id);
                        }
                      }),
                      onSubmit: () => harness.submissions++,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return harness;
  }

  Future<void> capture(String scene) async {
    if (_output.isEmpty) return;
    await tester.pump(const Duration(milliseconds: 500));
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await render.toImage(pixelRatio: 2);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(_output).create(recursive: true);
        await File(
          '$_output/$scene.png',
        ).writeAsBytes(data!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }
}
