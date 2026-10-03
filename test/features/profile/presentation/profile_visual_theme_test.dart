import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';
import 'package:y300/features/profile/presentation/user_profile_page.dart';
import 'package:y300/features/profile/presentation/widgets/profile_content.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

import '../../../test_support/localized_test_app.dart';

const _output = String.fromEnvironment('PROFILE_VISUAL_OUTPUT');
const _font = String.fromEnvironment('PROFILE_VISUAL_FONT');
const _capture = Key('profile-visual-capture');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    if (_output.isEmpty) return;
    if (_font.isNotEmpty) {
      await (FontLoader(
        'ProfileVisual',
      )..addFont(File(_font).readAsBytes().then(ByteData.sublistView))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final family in AppThemeFamily.values) {
    for (final brightness in Brightness.values) {
      for (final self in [false, true]) {
        for (final large in [false, true]) {
          final name =
              '${family.name}-${brightness.name}-${self ? 'self' : 'public'}-${large ? 'large' : 'normal'}';
          testWidgets('$name keeps identity and all operations accessible', (
            tester,
          ) async {
            await _pump(tester, family, brightness, self: self, large: large);
            final l10n = AppLocalizations.of(
              tester.element(find.byType(ProfileContent)),
            );
            expect(
              find.byKey(const Key('user-profile-identity')),
              findsOneWidget,
            );
            expect(
              find.text(l10n.profileUid(self ? '101' : '8')),
              findsOneWidget,
            );
            expect(
              find.byKey(
                Key(
                  self
                      ? 'user-profile-action-settings'
                      : 'user-profile-action-sendMessage',
                ),
              ),
              findsOneWidget,
            );
            await _save(tester, name);
            for (final kind
                in self
                    ? [
                        'threads',
                        'replies',
                        'blogs',
                        'messages',
                        'forumFavorites',
                        'friends',
                        'creditHistory',
                      ]
                    : ['addFriend', 'threads', 'replies', 'blogs']) {
              final button = find.byKey(Key('user-profile-action-$kind'));
              await tester.ensureVisible(button);
              await tester.pumpAndSettle();
              expect(button.hitTestable(), findsOneWidget);
              expect(tester.takeException(), isNull);
            }
            await tester.ensureVisible(find.text('2026-10-01 22:31'));
            await tester.pumpAndSettle();
            expect(find.text('2004-10-20 00:00'), findsOneWidget);
            expect(find.text('2048'), findsOneWidget);
            expect(tester.takeException(), isNull);
            if (!large) await _save(tester, '$name-details');
          });
        }
      }
    }
  }

  testWidgets(
    'traditional Chinese profile uses translated controls and preserves server text',
    (tester) async {
      await _pump(
        tester,
        AppThemeFamily.moonWhite,
        Brightness.light,
        locale: const Locale('zh', 'TW'),
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ProfileContent)),
      );
      expect(find.text(l10n.profileSendMessage), findsOneWidget);
      expect(find.text(l10n.profileAddFriend), findsOneWidget);
      expect(find.text('夏日回声'), findsOneWidget);
      await tester.ensureVisible(find.text('普通会员').first);
      expect(find.text('普通会员'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('wide profile keeps bounded reading width', (tester) async {
    await _pump(
      tester,
      AppThemeFamily.plumPurple,
      Brightness.dark,
      width: 1000,
    );
    expect(
      tester.getSize(find.byKey(const Key('user-profile-identity'))).width,
      lessThanOrEqualTo(760),
    );
    expect(tester.takeException(), isNull);
    await _save(tester, 'wide-public');
  });

  testWidgets(
    'signature and website links invoke navigation with the original URL',
    (tester) async {
      final links = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [imageCacheServiceProvider.overrideWithValue(_Images())],
          child: LocalizedTestApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: ProfileContent(
                profile: _profile(
                  false,
                  signatureHtml:
                      '<p><a href="https://example.test/story">故事链接</a></p>',
                ),
                capabilities: _capabilities,
                imageReferer: 'https://bbs.yamibo.com/',
                isMyProfile: false,
                onAction: (_) {},
                onOpenLink: links.add,
                onCopyUid: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final signatureLink = find.text('故事链接', findRichText: true);
      await tester.dragUntilVisible(
        signatureLink,
        find.byKey(const Key('user-profile-page-list')),
        const Offset(0, -250),
      );
      await tester.pumpAndSettle();
      final paragraph = tester.renderObject<RenderParagraph>(signatureLink);
      final linkBox = paragraph
          .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 4),
          )
          .first;
      await tester.tapAt(paragraph.localToGlobal(linkBox.toRect().center));
      await tester.dragUntilVisible(
        find.text('https://example.test/works'),
        find.byKey(const Key('user-profile-page-list')),
        const Offset(0, -250),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('https://example.test/works'));
      expect(links, [
        'https://example.test/story',
        'https://example.test/works',
      ]);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pump(
  WidgetTester tester,
  AppThemeFamily family,
  Brightness brightness, {
  bool self = false,
  bool large = false,
  double? width,
  Locale locale = const Locale('zh'),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width ?? (large ? 300 : 390), 844);
  addTearDown(tester.view.reset);
  var theme = AppTheme.build(family: family, brightness: brightness);
  if (_output.isNotEmpty && _font.isNotEmpty) {
    theme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: 'ProfileVisual'),
    );
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        verifiedProfileOwnerProvider.overrideWithValue((
          uid: '101',
          revision: 1,
        )),
        forumUserProfileRepositoryProvider.overrideWithValue(
          _Repository(_profile(self)),
        ),
        forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
        imageCacheServiceProvider.overrideWithValue(_Images()),
      ],
      child: RepaintBoundary(
        key: _capture,
        child: LocalizedTestApp(
          theme: theme,
          debugShowCheckedModeBanner: false,
          locale: locale,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
            child: child!,
          ),
          home: self ? const MyProfilePage() : const UserProfilePage(uid: '8'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _capabilities = ForumUserProfileReadCapabilities(
  values: DataCapabilitySet.from(supported: ForumUserProfileCapability.values),
);

ForumUserProfileData _profile(bool self, {String? signatureHtml}) =>
    ForumUserProfileData(
      identity: ProfileUserIdentity(
        userId: self ? '101' : '8',
        displayName: '夏日回声',
      ),
      viewerUserId: '101',
      groupName: '普通会员',
      customTitle: '在故事与日常之间',
      isOnline: true,
      metrics: const [
        ForumUserProfileMetric(label: '总积分', value: '2048'),
        ForumUserProfileMetric(label: '积分', value: '1900 点'),
        ForumUserProfileMetric(label: '对象', value: '128'),
      ],
      signatureHtml: signatureHtml ?? '<p>把喜欢的故事，留在温柔的日常里。</p>',
      details: [
        ForumUserProfileDetail(
          label: 'UID',
          value: self ? '101' : '8',
          section: ForumUserProfileDetailSection.account,
        ),
        const ForumUserProfileDetail(
          label: '用户组',
          value: '普通会员',
          section: ForumUserProfileDetailSection.account,
        ),
        const ForumUserProfileDetail(
          label: '个人主页',
          value: 'https://example.test/works',
        ),
        const ForumUserProfileDetail(label: '最新记录', value: '正在读一本新书'),
        const ForumUserProfileDetail(
          label: '在线时间',
          value: '4875 小时',
          section: ForumUserProfileDetailSection.activity,
        ),
        const ForumUserProfileDetail(
          label: '注册时间',
          value: '2004-10-20 00:00',
          section: ForumUserProfileDetailSection.activity,
        ),
        const ForumUserProfileDetail(
          label: '最后访问',
          value: '2026-10-01 22:31',
          section: ForumUserProfileDetailSection.activity,
        ),
      ],
      actions: self
          ? [
              ForumUserProfileActionKind.threads,
              ForumUserProfileActionKind.blogs,
              ForumUserProfileActionKind.messages,
              ForumUserProfileActionKind.settings,
              ForumUserProfileActionKind.forumFavorites,
              ForumUserProfileActionKind.friends,
              ForumUserProfileActionKind.creditHistory,
            ]
          : [
              ForumUserProfileActionKind.threads,
              ForumUserProfileActionKind.blogs,
              ForumUserProfileActionKind.sendMessage,
              ForumUserProfileActionKind.addFriend,
            ],
    );

class _Repository implements ForumUserProfileRepository {
  _Repository(this.data);
  final ForumUserProfileData data;
  @override
  ForumUserProfileSourceCapabilities get capabilities =>
      ForumUserProfileSourceCapabilities(values: _capabilities.values);
  @override
  Future<DataReadResult<ForumUserProfileData, ForumUserProfileReadCapabilities>>
  load(
    ForumUserProfileQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    ForumRequestCancellation? cancellation,
  }) async => DataReadSuccess(
    data: data,
    capabilities: _capabilities,
    metadata: const DataReadMetadata.network(),
  );
}

class _Images implements ImageCacheService {
  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async =>
      CachedImageResult.failed;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _save(WidgetTester tester, String name) async {
  if (_output.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final frame = await boundary.toImage();
    try {
      final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
      final directory = await Directory(_output).create(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      frame.dispose();
    }
  });
}
