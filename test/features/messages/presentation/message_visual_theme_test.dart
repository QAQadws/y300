import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/messages/data/message_repository_provider.dart';
import 'package:y300/features/messages/presentation/message_center_page.dart';
import 'package:y300/features/messages/presentation/message_feed_providers.dart';
import 'package:y300/features/messages/presentation/new_private_message_page.dart';
import 'package:y300/features/messages/presentation/private_conversation_page.dart';
import 'package:y300/features/messages/presentation/widgets/message_read_status.dart';
import 'package:y300/features/messages/presentation/widgets/message_surface.dart';
import 'package:y300/features/messages/presentation/widgets/message_avatar.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_content_view.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_native_surface.dart';
import 'package:y300/shared/widgets/forum_cached_avatar.dart';

import '../../../test_support/localized_test_app.dart';
import '../support/message_test_repository.dart';
import '../support/message_avatar_test_cache.dart';

// Ordinary regression runs require no local font or screenshot directory.
// Review exports opt in to a real CJK font, avoiding the test runner's Ahem.
const _output = String.fromEnvironment('MESSAGE_VISUAL_OUTPUT');
const _font = String.fromEnvironment('MESSAGE_VISUAL_FONT');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (_font.isEmpty) return;
    final data = ByteData.sublistView(await File(_font).readAsBytes());
    for (final family in ['Ahem', 'Roboto']) {
      final loader = FontLoader(family)..addFont(Future.value(data));
      await loader.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final family in AppThemeFamily.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        '${family.name} ${brightness.name} uses native message surfaces throughout',
        (tester) async {
          final theme = AppTheme.build(family: family, brightness: brightness);
          final palette = theme.y300NativeContent;
          final harness = _Harness(tester, theme);
          await harness.size(const Size(390, 844));
          await harness.show(_center());
          harness.repository.reads.single.result.complete(
            messageTestPage(_directory),
          );
          await tester.pumpAndSettle();
          _expectSurfaces(tester, theme);
          final tabs = tester.widget<TabBar>(find.byType(TabBar));
          final foreground = theme.appBarTheme.foregroundColor!;
          expect(tabs.labelColor, foreground);
          expect(tabs.unselectedLabelColor, foreground.withValues(alpha: 0.72));
          expect(tabs.indicatorColor, foreground);
          expect(
            _contrast(foreground, theme.appBarTheme.backgroundColor!),
            greaterThanOrEqualTo(4.5),
          );
          final badge = tester.widget<Badge>(find.byType(Badge).first);
          expect(badge.backgroundColor, palette.notificationBadgeBackground);
          expect(badge.textColor, palette.selectionForeground);
          final avatar = tester.widget<ForumCachedAvatar>(
            find.byType(ForumCachedAvatar).first,
          );
          expect(avatar.imageUrl, MessageAvatarTestCache.aliceUrl);
          expect(
            tester.getSize(find.byType(MessageAvatar).first),
            const Size.square(40),
          );
          expect(tester.getRect(find.byType(MessageSurface).first).left, 10);
          final title = tester.widget<Text>(find.text('一起读书的朋友'));
          expect(title.style!.color, palette.itemTitle);
          await harness.capture('messages');

          await tester.tap(find.text(harness.l10n.messageNotificationsTab));
          await tester.pump();
          harness.repository.notificationReads.single.result.complete(
            notificationTestPage([
              notificationTestItem(
                '1',
                duplicateCount: 2,
                avatarUrl: MessageAvatarTestCache.aliceUrl,
                markup:
                    '<p>回复了你的帖子：<a href="forum.php?mod=viewthread&amp;tid=42">周末阅读分享</a></p>',
              ),
              notificationTestItem(
                '2',
                authorId: '0',
                markup: '<p>欢迎回来，祝你阅读愉快。</p>',
              ),
            ]),
          );
          await tester.pumpAndSettle();
          _expectSurfaces(tester, theme);
          for (final view in tester.widgetList<ForumHtmlContentView>(
            find.byType(ForumHtmlContentView),
          )) {
            expect(view.surfaceColor, palette.card);
            expect(view.foregroundColor, palette.body);
          }
          await harness.capture('notifications');
          await tester.tap(find.byTooltip(harness.l10n.messageIgnore).first);
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<AlertDialog>(find.byType(AlertDialog))
                .backgroundColor,
            isNull,
          );
          await harness.capture('ignore');

          await harness.show(
            const PrivateConversationPage(
              target: ForumConversationTarget.direct('20'),
              title: '一起读书的朋友',
              onOpenLink: _ignoreLink,
            ),
          );
          harness.repository.reads.single.result.complete(
            messageTestPage([
              messageTestItem(
                '1',
                senderAvatarUrl: MessageAvatarTestCache.aliceUrl,
                html: '<p>这段故事很喜欢。</p><p><b>你读到哪一章了？</b></p>',
              ),
              messageTestItem(
                '2',
                sender: '10',
                senderAvatarUrl: MessageAvatarTestCache.meUrl,
                html: '<p>刚看完第三章，<i>周末继续聊</i>。</p>',
              ),
              messageTestItem('3', sender: '10', html: '<p>嗯</p>'),
              messageTestItem('4', html: '<p>好呀，下次见！</p>'),
            ]),
          );
          await tester.pumpAndSettle();
          final bodies = tester
              .widgetList<ForumHtmlContentView>(
                find.byType(ForumHtmlContentView),
              )
              .toList();
          final incoming = bodies.singleWhere(
            (body) => body.sourceId.endsWith(':1'),
          );
          final outgoing = bodies.singleWhere(
            (body) => body.sourceId.endsWith(':2'),
          );
          expect(incoming.surfaceColor, palette.card);
          expect(
            outgoing.surfaceColor,
            Color.alphaBlend(
              palette.accent.withValues(alpha: 0.10),
              palette.card,
            ),
          );
          expect(outgoing.foregroundColor, palette.body);
          expect(find.byType(MessageSurface), findsNothing);
          for (final id in ['1', '2', '3', '4']) {
            final bubble = tester.widget<Material>(
              find.byKey(ValueKey('conversation-bubble-$id')),
            );
            expect(bubble.elevation, 0);
            expect(bubble.borderRadius, BorderRadius.circular(16));
          }
          expect(
            tester
                .getSize(find.byKey(const ValueKey('conversation-bubble-3')))
                .width,
            lessThan(
              tester
                  .getSize(find.byKey(const ValueKey('conversation-bubble-2')))
                  .width,
            ),
          );
          expect(
            _contrast(palette.body, outgoing.surfaceColor!),
            greaterThanOrEqualTo(4.5),
          );
          _expectInputTheme(tester, theme);
          await harness.capture('conversation');

          await harness.show(
            const PrivateConversationPage(
              target: ForumConversationTarget.group('91'),
              title: '周末读书小组',
              onOpenLink: _ignoreLink,
            ),
          );
          harness.repository.reads.single.result.complete(
            messageTestPage([
              _chatItem('1', html: '<p>大家周末想读哪本？</p>'),
              _chatItem('2', minute: 1, html: '<p>这篇的设定很有趣。</p>'),
              _chatItem(
                '3',
                sender: '30',
                name: '小林',
                minute: 2,
                html: '<p>我投它一票！</p>',
              ),
              _chatItem('4', sender: '10', minute: 3, html: '<p>好呀</p>'),
              _chatItem('5', minute: 10, html: '<p>那我们下周分享感想。</p>'),
            ], anchor: '5'),
          );
          await tester.pumpAndSettle();
          await harness.capture('group');

          await harness.show(
            const PrivateConversationPage(
              target: ForumConversationTarget.direct('20'),
              title: '一起读书的朋友',
              onOpenLink: _ignoreLink,
            ),
          );
          harness.repository.reads.single.result.complete(
            messageTestPage([
              for (var id = 1; id <= 24; id++)
                _chatItem(
                  '$id',
                  sender: id.isEven ? '10' : '20',
                  minute: id,
                  html:
                      '<p>${id.isEven ? '我也很喜欢她们重逢的那一段。' : '读到这里的时候，很想找你聊聊。'}</p>',
                ),
            ]),
          );
          await tester.pumpAndSettle();
          await harness.capture('long-latest');
          tester.view.viewInsets = const FakeViewPadding(bottom: 260);
          await tester.enterText(
            find.byKey(const Key('message-input')),
            '刚读完这一章。\n想分享几句感想，\n周末一起聊！',
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('message-send')).hitTestable(),
            findsOneWidget,
          );
          final sendStyle = tester
              .widget<IconButton>(find.byKey(const Key('message-send')))
              .style!;
          expect(
            _contrast(
              sendStyle.foregroundColor!.resolve({})!,
              sendStyle.backgroundColor!.resolve({})!,
            ),
            greaterThanOrEqualTo(4.5),
          );
          await harness.capture('multiline-keyboard');
          tester.view.resetViewInsets();

          await harness.show(
            const PrivateConversationPage(
              target: ForumConversationTarget.direct('20'),
              title: '一起读书的朋友',
              onOpenLink: _ignoreLink,
            ),
          );
          harness.repository.reads.single.result.complete(
            messageTestPage([
              _chatItem(
                '1',
                html:
                    '<p>整理了一点阅读计划：</p><blockquote>慢慢读，也是一种享受。</blockquote><table><tr><td>周六</td><td>前三章</td></tr><tr><td>周日</td><td>分享感想</td></tr></table><p><a href="forum.php?mod=viewthread&amp;tid=42">打开讨论帖</a></p>',
              ),
              _chatItem('2', sender: '10', html: '<p>收到！</p>'),
            ]),
          );
          await tester.pumpAndSettle();
          await harness.capture('rich-content');

          await harness.show(const NewPrivateMessagePage());
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('message-recipient')),
            '一起读书的朋友',
          );
          await tester.enterText(
            find.byKey(const Key('message-input')),
            '你好，想和你聊聊最近读到的故事。',
          );
          await tester.pumpAndSettle();
          _expectInputTheme(tester, theme);
          await harness.capture('compose');
          await harness.export('${family.name}-${brightness.name}');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('narrow large text and keyboard keep message actions reachable', (
    tester,
  ) async {
    final harness = _Harness(
      tester,
      AppTheme.build(
        family: AppThemeFamily.plumPurple,
        brightness: Brightness.dark,
      ),
      textScale: 1.8,
    );
    await harness.size(const Size(320, 740));
    await harness.show(_center());
    harness.repository.reads.single.result.complete(
      messageTestPage(_directory),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await harness.capture('narrow-list');
    await tester.tap(find.text(harness.l10n.messageNotificationsTab));
    await tester.pump();
    harness.repository.notificationReads.single.result.complete(
      notificationTestPage([
        notificationTestItem(
          '1',
          avatarUrl: MessageAvatarTestCache.aliceUrl,
          markup: '<p>一段很长的提醒，<b>保留富文本</b>和原来的链接。</p>',
        ),
      ]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(harness.l10n.messageIgnore));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('notification-ignore-save')).hitTestable(),
      findsOneWidget,
    );
    await harness.capture('narrow-ignore');
    await harness.show(
      const PrivateConversationPage(
        target: ForumConversationTarget.direct('20'),
        title: '长名称的读书朋友',
        onOpenLink: _ignoreLink,
      ),
    );
    harness.repository.reads.single.result.complete(
      messageTestPage([
        messageTestItem(
          '1',
          senderAvatarUrl: MessageAvatarTestCache.aliceUrl,
          html: '<p>第一行</p><p>第二行的消息内容</p>',
        ),
      ]),
    );
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.enterText(find.byKey(const Key('message-input')), '回复内容');
    await tester.pumpAndSettle();
    final send = find.byKey(const Key('message-send'));
    await tester.ensureVisible(send);
    await tester.pumpAndSettle();
    expect(send.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await harness.capture('keyboard');
    await harness.export('narrow-large-text');
  });

  testWidgets('wide conversation keeps the reading canvas centered', (
    tester,
  ) async {
    final harness = _Harness(tester, AppTheme.light());
    await harness.size(const Size(1280, 900));
    await harness.show(
      const PrivateConversationPage(
        target: ForumConversationTarget.direct('20'),
        title: '一起读书的朋友',
        onOpenLink: _ignoreLink,
      ),
    );
    harness.repository.reads.single.result.complete(
      messageTestPage([
        _chatItem('1', html: '<p>嗯</p>'),
        _chatItem(
          '2',
          sender: '10',
          html: '<p>${List.filled(12, '周末一起分享最近读到的故事。').join()}</p>',
        ),
      ]),
    );
    await tester.pumpAndSettle();
    final canvas = tester.getRect(
      find.byKey(const Key('private-conversation-list')),
    );
    expect(canvas.width, 840);
    expect(canvas.center.dx, 640);
    await harness.capture('wide-conversation');
    await harness.export('wide');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'loading, failure, empty and logged-out states use native surfaces',
    (tester) async {
      final theme = AppTheme.light();
      final palette = theme.y300NativeContent;
      final harness = _Harness(tester, theme);
      await harness.size(const Size(390, 844));
      await harness.show(_center());
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .color,
        palette.accent,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await harness.capture('loading');
      harness.repository.reads.single.result.complete(
        const DataReadFailure(
          kind: DataReadFailureKind.network,
          code: 'fixture',
          diagnosticMessage: 'fixture',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MessageReadStatus), findsOneWidget);
      await harness.capture('failure');
      await tester.tap(find.text(harness.l10n.commonRetry));
      await tester.pump();
      harness.repository.reads.last.result.complete(messageTestPage([]));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.text(harness.l10n.profileNoMessages))
            .style!
            .color,
        palette.supportingText,
      );
      await harness.capture('empty');
      await harness.show(_center(), account: null);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        palette.background,
      );
      expect(
        tester
            .widget<Text>(find.text(harness.l10n.messageLoginRequired))
            .style!
            .color,
        palette.supportingText,
      );
      await harness.capture('login');
      await harness.export('states');
      expect(tester.takeException(), isNull);
    },
  );
}

MessageCenterPage _center() => MessageCenterPage(
  onOpenConversation: (_, _, _) {},
  onOpenLink: _ignoreLink,
  onOpenUser: (_, _) {},
);
void _ignoreLink(BuildContext context, String url) {}

ForumPrivateMessageItem _chatItem(
  String id, {
  required String html,
  String sender = '20',
  String name = '一起读书的朋友',
  int minute = 0,
}) => ForumPrivateMessageItem(
  messageId: id,
  conversationId: '91',
  isNew: false,
  subject: '',
  fromUserId: sender,
  fromUserName: sender == '10' ? '我' : name,
  fromUserAvatarUrl: sender == '10'
      ? MessageAvatarTestCache.meUrl
      : MessageAvatarTestCache.aliceUrl,
  toUserId: sender == '10' ? '20' : '10',
  toUserName: sender == '10' ? name : '我',
  message: html,
  sentAt: DateTime(2026, 9, 27, 14, minute),
  rawDateline: '',
);

const _directory = [
  ForumPrivateMessageItem(
    messageId: '1',
    conversationId: '91',
    isNew: true,
    subject: '',
    fromUserId: '20',
    fromUserName: '一起读书的朋友',
    toUserId: '20',
    toUserName: '一起读书的朋友',
    toUserAvatarUrl: MessageAvatarTestCache.aliceUrl,
    message: '<p>你推荐的那篇小说看完了，结尾很喜欢。</p>',
    sentAt: null,
    rawDateline: '今天 10:30',
  ),
  ForumPrivateMessageItem(
    messageId: '2',
    conversationId: '92',
    isNew: false,
    subject: '一个名称比较长的周末阅读交流小组',
    fromUserId: '30',
    fromUserName: '朋友',
    toUserId: '0',
    toUserName: '',
    message: '<p>来分享这一周读到的故事吧。</p>',
    sentAt: null,
    rawDateline: '昨天 20:15',
    isGroupConversation: true,
    participantCount: 3,
  ),
];

void _expectSurfaces(WidgetTester tester, ThemeData theme) {
  expect(find.byType(Card), findsNothing);
  final surfaces = find.byType(MessageSurface);
  expect(surfaces, findsWidgets);
  for (final element in surfaces.evaluate()) {
    final finder = find.byWidget(element.widget);
    final box =
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: finder,
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(box.borderRadius, const BorderRadius.all(Radius.circular(12)));
    expect(
      box.boxShadow,
      ForumNativeSurfaceShadows.card(theme.y300NativeContent.stateLayer),
    );
    final material = tester.widget<Material>(
      find.descendant(of: finder, matching: find.byType(Material)).first,
    );
    expect(material.elevation, 0);
    expect(material.clipBehavior, Clip.antiAlias);
    expect(material.surfaceTintColor, Colors.transparent);
  }
}

void _expectInputTheme(WidgetTester tester, ThemeData theme) {
  final field = tester.widget<TextField>(
    find.byKey(const Key('message-input')),
  );
  expect(field.decoration!.border, isNull);
  expect(field.style!.color, theme.y300NativeContent.body);
  final decoration = tester.widget<InputDecorator>(
    find.descendant(
      of: find.byKey(const Key('message-input')),
      matching: find.byType(InputDecorator),
    ),
  );
  expect(
    decoration.decoration.enabledBorder,
    theme.inputDecorationTheme.enabledBorder,
  );
  expect(decoration.decoration.fillColor, theme.inputDecorationTheme.fillColor);
}

double _contrast(Color foreground, Color background) {
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  return first > second
      ? (first + 0.05) / (second + 0.05)
      : (second + 0.05) / (first + 0.05);
}

class _Harness {
  _Harness(this.tester, this.theme, {this.textScale = 1});
  final WidgetTester tester;
  final ThemeData theme;
  final double textScale;
  final boundary = GlobalKey();
  final images = <ui.Image>[];
  final labels = <String>[];
  late MessageTestRepository repository;
  late MessageAvatarTestCache avatars;

  AppLocalizations get l10n =>
      AppLocalizations.of(tester.element(find.byType(Scaffold).first));

  Future<void> size(Size size) async {
    avatars = await MessageAvatarTestCache.create(tester);
    tester.view.devicePixelRatio = 1;
    await tester.binding.setSurfaceSize(size);
    addTearDown(() async {
      tester.view.resetDevicePixelRatio();
      await tester.binding.setSurfaceSize(null);
      for (final image in images) {
        image.dispose();
      }
    });
  }

  Future<void> show(Widget page, {String? account = '10'}) async {
    await tester.pumpWidget(const SizedBox.shrink());
    repository = MessageTestRepository();
    final container = ProviderContainer.test(
      overrides: [
        messageAccountIdProvider.overrideWithValue(account),
        messageRepositoryProvider.overrideWithValue(repository),
        imageCacheServiceProvider.overrideWithValue(avatars),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          // The app normally resolves these unqualified styles through the
          // platform font fallback, which Flutter's test renderer lacks.
          theme: _font.isEmpty
              ? theme
              : theme.copyWith(
                  dialogTheme: theme.dialogTheme.copyWith(
                    titleTextStyle: theme.dialogTheme.titleTextStyle?.copyWith(
                      fontFamily: 'Roboto',
                    ),
                    contentTextStyle: theme.dialogTheme.contentTextStyle
                        ?.copyWith(fontFamily: 'Roboto'),
                  ),
                ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: RepaintBoundary(key: boundary, child: child!),
          ),
          home: page,
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> capture(String scene) async {
    await settleMessageAvatarImages(tester);
    if (_output.isEmpty) return;
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    void repaint(RenderObject object) {
      object.markNeedsPaint();
      object.visitChildren(repaint);
    }

    final disabledShadows = debugDisableShadows;
    try {
      // Export the real shadows, then restore the test binding's debug state.
      debugDisableShadows = false;
      repaint(render);
      await tester.pump();
      final image = await tester.runAsync(() => render.toImage(pixelRatio: 1));
      images.add(image!);
      labels.add(scene);
    } finally {
      debugDisableShadows = disabledShadows;
      repaint(render);
      await tester.pump();
    }
  }

  Future<void> export(String name) async {
    if (_output.isEmpty) return;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      var x = 0.0;
      await Directory(_output).create(recursive: true);
      for (var index = 0; index < images.length; index++) {
        final image = images[index];
        final sceneBytes = await image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        await File(
          '$_output/$name-${labels[index]}.png',
        ).writeAsBytes(sceneBytes!.buffer.asUint8List());
        canvas.drawRect(
          Rect.fromLTWH(x, 0, image.width.toDouble(), 30),
          Paint()..color = const Color(0xFF303030),
        );
        final label = TextPainter(
          text: TextSpan(
            text: labels[index],
            style: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 14,
              color: Colors.white,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(canvas, Offset(x + 8, 6));
        label.dispose();
        canvas.drawImage(image, Offset(x, 30), Paint());
        x += image.width;
      }
      final picture = recorder.endRecording();
      final sheet = await picture.toImage(x.toInt(), images.first.height + 30);
      try {
        final bytes = await sheet.toByteData(format: ui.ImageByteFormat.png);
        await Directory(_output).create(recursive: true);
        await File(
          '$_output/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        sheet.dispose();
        picture.dispose();
      }
    });
  }
}
