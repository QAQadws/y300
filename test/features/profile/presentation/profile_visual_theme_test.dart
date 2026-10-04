import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/auth/application/verified_session_owner.dart';
import 'package:y300/features/profile/presentation/user_profile_page.dart';
import 'package:y300/features/profile/presentation/widgets/profile_content.dart';
import 'package:y300/features/profile/presentation/widgets/profile_page_body.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

import '../../../test_support/localized_test_app.dart';

const _output = String.fromEnvironment('PROFILE_VISUAL_OUTPUT');
const _font = String.fromEnvironment('PROFILE_VISUAL_FONT');
const _capture = Key('profile-visual-capture');

final _ownerSource = StateProvider<VerifiedSessionOwner>(
  (ref) => (uid: '101', revision: 1),
);

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
          testWidgets('$name shows a bounded identity skeleton while loading', (
            tester,
          ) async {
            final repository = _ControlledRepository();
            await _pump(
              tester,
              family,
              brightness,
              self: self,
              large: large,
              repository: repository,
              settle: false,
            );
            expect(repository.requests, hasLength(1));
            expect(
              find.byKey(const Key('user-profile-identity-skeleton')),
              findsOneWidget,
            );
            final identity = find.byKey(const Key('user-profile-identity'));
            final card = tester.getRect(identity);
            final avatar = tester.getRect(
              find.byKey(const Key('user-profile-avatar-skeleton')),
            );
            expect(card.left, greaterThanOrEqualTo(20));
            expect(
              card.right,
              lessThanOrEqualTo(tester.view.physicalSize.width - 20),
            );
            expect(card.width, lessThanOrEqualTo(760));
            expect(avatar.size, const Size(72, 72));
            expect(card.contains(avatar.topLeft), isTrue);
            expect(card.contains(avatar.bottomRight), isTrue);
            expect(find.byType(CircularProgressIndicator), findsNothing);
            expect(find.byType(ProfileContent), findsNothing);
            for (final kind in ['addFriend', 'removeFriend', 'settings']) {
              expect(
                find.byKey(Key('user-profile-action-$kind')),
                findsNothing,
              );
            }
            expect(tester.takeException(), isNull);
            await _save(tester, '$name-loading');
          });

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
            final identity = find.byKey(const Key('user-profile-identity'));
            expect(
              tester.widget<Card>(identity).color,
              Theme.of(tester.element(identity)).y300NativeContent.card,
            );
            expect(
              find.descendant(
                of: find.byKey(const Key('user-profile-identity')),
                matching: find.byKey(const Key('user-profile-metrics')),
              ),
              findsOneWidget,
            );
            expect(
              find.text(l10n.profileUid(self ? '101' : '8')),
              findsOneWidget,
            );
            final settings = find.byKey(
              const Key('user-profile-action-settings'),
            );
            final contactActions = find.byKey(
              const Key('user-profile-contact-actions'),
            );
            final appBar = find.byType(AppBar);
            expect(
              find.descendant(
                of: appBar,
                matching: find.byIcon(Icons.home_outlined),
              ),
              findsNothing,
            );
            if (self) {
              expect(contactActions, findsNothing);
              expect(
                find.descendant(of: appBar, matching: settings),
                findsOneWidget,
              );
              expect(
                find.descendant(
                  of: find.byType(ProfileContent),
                  matching: settings,
                ),
                findsNothing,
              );
              expect(
                tester.widget<IconButton>(settings).tooltip,
                l10n.profileSettings,
              );
              expect(settings.hitTestable(), findsOneWidget);
            } else {
              expect(settings, findsNothing);
              expect(
                find.descendant(of: identity, matching: contactActions),
                findsOneWidget,
              );
              for (final kind in ['sendMessage', 'addFriend']) {
                final button = find.byKey(Key('user-profile-action-$kind'));
                expect(button, findsOneWidget);
                expect(
                  find.descendant(of: contactActions, matching: button),
                  findsOneWidget,
                );
                expect(tester.widget<TextButton>(button).onPressed, isNotNull);
              }
              if (!large) {
                final message = tester.getRect(
                  find.byKey(const Key('user-profile-action-sendMessage')),
                );
                final friend = tester.getRect(
                  find.byKey(const Key('user-profile-action-addFriend')),
                );
                expect(message.center.dy, closeTo(friend.center.dy, 0.5));
                expect(message.right, lessThanOrEqualTo(friend.left));
              }
            }
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
                    : [
                        'sendMessage',
                        'addFriend',
                        'threads',
                        'replies',
                        'blogs',
                      ]) {
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

  testWidgets('self skeleton keeps card height and content heading in place', (
    tester,
  ) async {
    final repository = _ControlledRepository();
    await _pump(
      tester,
      AppThemeFamily.warmPaper,
      Brightness.light,
      self: true,
      repository: repository,
      settle: false,
    );
    final identity = find.byKey(const Key('user-profile-identity'));
    final l10n = AppLocalizations.of(tester.element(identity));
    final heading = find.text(l10n.profileMyContent);
    final loadingHeight = tester.getSize(identity).height;
    final loadingHeadingTop = tester.getTopLeft(heading).dy;
    await _save(tester, 'profile-self-height-loading');

    repository.complete(_profile(true));
    await tester.pumpAndSettle();

    expect(tester.getSize(identity).height, closeTo(loadingHeight, 0.01));
    expect(tester.getTopLeft(heading).dy, closeTo(loadingHeadingTop, 0.01));
    expect(
      find.byKey(const Key('user-profile-identity-skeleton')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await _save(tester, 'profile-self-height-loaded');
  });

  testWidgets(
    'reduced motion reveals only the newly verified owner immediately',
    (tester) async {
      final repository = _ControlledRepository();
      await _pump(
        tester,
        AppThemeFamily.warmPaper,
        Brightness.light,
        self: true,
        repository: repository,
        settle: false,
        disableAnimations: true,
      );
      repository.complete(_profile(true, displayName: 'old-owner'));
      await tester.pump();
      await tester.pump();

      double contentOpacity() => tester
          .widget<Opacity>(
            find
                .descendant(
                  of: find.byType(ProfileContent),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity;
      expect(contentOpacity(), 1);
      expect(
        find.byKey(const Key('user-profile-identity-skeleton')),
        findsNothing,
      );
      expect(find.text('old-owner'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ProfileContent)),
      );

      ScrollableState scrollable() => tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const Key('user-profile-page-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final oldScrollable = scrollable();
      oldScrollable.position.jumpTo(40);
      await tester.pump();

      container.read(_ownerSource.notifier).state = (uid: '101', revision: 2);
      await tester.pump();
      expect(scrollable(), isNot(same(oldScrollable)));
      expect(scrollable().position.pixels, 0);
      expect(repository.requests, hasLength(2));
      expect(find.byType(ProfileContent, skipOffstage: false), findsNothing);
      expect(find.text('old-owner', skipOffstage: false), findsNothing);
      expect(
        find.byKey(const Key('user-profile-identity-skeleton')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('user-profile-action-settings')),
        findsNothing,
      );

      repository.complete(_profile(true, displayName: 'current-owner'));
      await tester.pump();
      await tester.pump();

      expect(contentOpacity(), 1);
      expect(find.text('current-owner'), findsOneWidget);
      expect(find.text('old-owner', skipOffstage: false), findsNothing);
      expect(
        find.byKey(const Key('user-profile-identity-skeleton')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('loading then refreshing preserves the profile viewport', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final repository = _ControlledRepository();
      await _pump(
        tester,
        AppThemeFamily.moonWhite,
        Brightness.light,
        repository: repository,
        settle: false,
      );
      final identity = find.byKey(const Key('user-profile-identity'));
      final loadingTop = tester.getTopLeft(identity);
      final loadingAvatar = tester.getRect(
        find.byKey(const Key('user-profile-avatar-skeleton')),
      );
      final l10n = AppLocalizations.of(tester.element(identity));
      expect(find.bySemanticsLabel(l10n.profileLoading), findsOneWidget);
      await _save(tester, 'profile-transition-loading');

      repository.complete(_profile(false));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('user-profile-identity-skeleton')),
        findsNothing,
      );
      expect(tester.getTopLeft(identity), loadingTop);
      final avatar = find.byKey(const Key('user-profile-avatar'));
      expect(tester.getRect(avatar), loadingAvatar);
      final friend = find.byKey(const Key('user-profile-action-addFriend'));
      expect(tester.widget<TextButton>(friend).onPressed, isNotNull);
      await _save(tester, 'profile-transition-loaded');

      final list = find.byKey(const Key('user-profile-page-list'));
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)).first,
      );
      scrollable.position.jumpTo(40);
      await tester.pump();
      final previousOffset = scrollable.position.pixels;
      final previousCard = tester.getRect(identity);
      final previousAvatar = tester.getRect(avatar);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ProfileContent)),
      );
      final refresh = container
          .read(userProfileProvider('8').notifier)
          .refresh();
      await tester.pump();
      expect(repository.requests, hasLength(2));
      expect(
        find.byKey(const Key('user-profile-refresh-progress')),
        findsOneWidget,
      );
      expect(tester.getRect(identity), previousCard);
      expect(tester.getRect(avatar), previousAvatar);
      expect(scrollable.position.pixels, previousOffset);
      expect(tester.widget<TextButton>(friend).onPressed, isNotNull);
      await _save(tester, 'profile-transition-refresh');

      repository.complete(_profile(false));
      await tester.pumpAndSettle();
      await refresh;
      expect(
        find.byKey(const Key('user-profile-refresh-progress')),
        findsNothing,
      );
      expect(tester.getRect(identity), previousCard);
      expect(tester.getRect(avatar), previousAvatar);
      expect(scrollable.position.pixels, previousOffset);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

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
      final contactActions = find.byKey(
        const Key('user-profile-contact-actions'),
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('user-profile-identity')),
          matching: contactActions,
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: contactActions,
          matching: find.text(l10n.profileSendMessage),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: contactActions,
          matching: find.text(l10n.profileAddFriend),
        ),
        findsOneWidget,
      );
      expect(find.text('夏日回声'), findsOneWidget);
      await tester.ensureVisible(find.text('普通会员').first);
      expect(find.text('普通会员'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('public card exposes only the advertised removal action', (
    tester,
  ) async {
    await _pump(
      tester,
      AppThemeFamily.plumPurple,
      Brightness.dark,
      large: true,
      profile: _profile(
        false,
        actions: const [ForumUserProfileActionKind.removeFriend],
      ),
    );
    final contactActions = find.byKey(
      const Key('user-profile-contact-actions'),
    );
    final remove = find.byKey(const Key('user-profile-action-removeFriend'));
    expect(
      find.descendant(
        of: find.byKey(const Key('user-profile-identity')),
        matching: contactActions,
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: contactActions, matching: remove),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('user-profile-action-addFriend')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('user-profile-action-sendMessage')),
      findsNothing,
    );
    final l10n = AppLocalizations.of(tester.element(remove));
    expect(find.text(l10n.profileRemoveFriend), findsOneWidget);
    await tester.ensureVisible(remove);
    await tester.pumpAndSettle();
    expect(remove.hitTestable(), findsOneWidget);
    expect(tester.widget<TextButton>(remove).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await _save(tester, 'public-remove-friend-only-large');
  });

  for (final self in [false, true]) {
    testWidgets(
      'unverified actions expose no contact or settings, self=$self',
      (tester) async {
        await _pump(
          tester,
          AppThemeFamily.warmPaper,
          Brightness.light,
          self: self,
          capabilities: ForumUserProfileReadCapabilities(
            values: DataCapabilitySet.from(
              supported: ForumUserProfileCapability.values.where(
                (capability) =>
                    capability != ForumUserProfileCapability.orderedActions,
              ),
            ),
          ),
        );
        expect(find.byKey(const Key('user-profile-identity')), findsOneWidget);
        expect(
          find.byKey(const Key('user-profile-contact-actions')),
          findsNothing,
        );
        for (final kind in [
          'sendMessage',
          'addFriend',
          'removeFriend',
          'settings',
        ]) {
          expect(find.byKey(Key('user-profile-action-$kind')), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

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

  testWidgets('profile details keep source order in a single surface', (
    tester,
  ) async {
    await _pump(tester, AppThemeFamily.warmPaper, Brightness.light);
    final details = find.byKey(const Key('user-profile-details'));
    final l10n = AppLocalizations.of(tester.element(details));
    expect(find.text(l10n.profileDetails), findsOneWidget);
    expect(
      find.descendant(of: details, matching: find.byType(ProfileSurface)),
      findsOneWidget,
    );
    // Source fields deliberately mix semantic sections; their order must stay.
    var previousY = double.negativeInfinity;
    for (final entry in _profile(false).details) {
      final label = find.descendant(
        of: details,
        matching: find.text(entry.label),
      );
      final currentY = tester.getTopLeft(label).dy;
      expect(currentY, greaterThan(previousY), reason: entry.label);
      previousY = currentY;
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('header omits the credit unit and leaves extra metrics below', (
    tester,
  ) async {
    const metrics = [
      ForumUserProfileMetric(label: '总积分', value: '0'),
      ForumUserProfileMetric(label: '积分', value: '-1 点'),
      ForumUserProfileMetric(label: '对象', value: '128'),
      ForumUserProfileMetric(label: '纪念币', value: '9 枚'),
    ];
    await _pump(
      tester,
      AppThemeFamily.warmPaper,
      Brightness.light,
      profile: _profile(false, metrics: metrics),
    );
    final identity = find.byKey(const Key('user-profile-identity'));
    final avatar = tester.getRect(find.byKey(const Key('user-profile-avatar')));
    var previousX = avatar.right;
    for (final metric in metrics.take(3)) {
      final displayValue = metric.label == '积分' ? '-1' : metric.value;
      final value = find.descendant(
        of: identity,
        matching: find.text(displayValue),
      );
      final label = find.descendant(
        of: identity,
        matching: find.text(metric.label),
      );
      expect(value, findsOneWidget);
      expect(tester.getTopLeft(value).dx, greaterThan(previousX));
      expect(tester.getBottomLeft(label).dy, closeTo(avatar.bottom, 0.1));
      previousX = tester.getTopLeft(value).dx;
      expect(find.text(displayValue), findsOneWidget);
    }
    expect(find.text('-1 点'), findsNothing);
    final extra = find.byKey(const Key('user-profile-additional-metrics'));
    expect(
      find.descendant(of: identity, matching: find.text(metrics.last.value)),
      findsNothing,
    );
    expect(
      find.descendant(of: extra, matching: find.text(metrics.last.value)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing statistics do not invent balances', (tester) async {
    await _pump(
      tester,
      AppThemeFamily.moonWhite,
      Brightness.light,
      profile: _profile(false, metrics: []),
    );
    expect(find.byKey(const Key('user-profile-metrics')), findsNothing);
    expect(
      find.byKey(const Key('user-profile-additional-metrics')),
      findsNothing,
    );
    expect(find.byKey(const Key('user-profile-copy-uid')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _save(tester, 'no-statistics');
  });

  testWidgets('long balances reflow and expose their full text', (
    tester,
  ) async {
    const displayValue = '123456789012345678901234567890';
    const longValue = '$displayValue 点';
    await _pump(
      tester,
      AppThemeFamily.warmPaper,
      Brightness.light,
      large: true,
      profile: _profile(
        false,
        metrics: const [
          ForumUserProfileMetric(label: '总积分', value: '2048'),
          ForumUserProfileMetric(label: '积分', value: longValue),
          ForumUserProfileMetric(label: '对象', value: '128'),
        ],
      ),
    );
    final total = find.text('2048');
    final credits = find.text(displayValue);
    expect(
      tester.getTopLeft(credits).dy,
      greaterThan(tester.getBottomLeft(total).dy),
    );
    final text = tester.widget<Text>(total);
    final rendered = tester.renderObject<RenderParagraph>(total);
    expect(rendered.didExceedMaxLines, isFalse);
    expect(text.maxLines, 1);
    await _save(tester, 'large-long-balances');
    final l10n = AppLocalizations.of(tester.element(credits));
    await tester.longPress(credits);
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.moreAccountStatistic('积分', displayValue)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final large in [false, true]) {
    testWidgets(
      'title sits below identity without changing height, large=$large',
      (tester) async {
        final profile = _profile(
          false,
          displayName: '夏日',
          customTitle: '晴日',
          isOnline: false,
        );
        await _pump(
          tester,
          AppThemeFamily.warmPaper,
          Brightness.light,
          large: large,
          profile: profile,
        );
        final identity = find.byKey(const Key('user-profile-identity'));
        final title = find.byKey(const Key('user-profile-custom-title'));
        final group = find.descendant(
          of: identity,
          matching: find.text(profile.groupName!),
        );
        final name = find.byKey(const Key('user-profile-name'));
        final copyUid = find.byKey(const Key('user-profile-copy-uid'));
        final withTitleHeight = tester.getSize(identity).height;
        expect(
          tester.getTopLeft(title).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(name).dy),
        );
        expect(
          tester.getTopLeft(title).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(group).dy),
        );
        if (!large) {
          expect(
            tester.getCenter(name).dy,
            closeTo(tester.getCenter(group).dy, 0.5),
          );
          expect(
            tester.getTopLeft(group).dx,
            greaterThan(tester.getTopRight(name).dx),
          );
          expect(
            tester.getCenter(name).dy,
            closeTo(tester.getCenter(copyUid).dy, 0.5),
          );
        }
        await _save(
          tester,
          'identity-${large ? 'large' : 'normal'}-with-title',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await _pump(
          tester,
          AppThemeFamily.warmPaper,
          Brightness.light,
          large: large,
          profile: _profile(
            false,
            displayName: profile.identity.displayName,
            customTitle: null,
            isOnline: false,
          ),
        );
        expect(tester.getSize(identity).height, closeTo(withTitleHeight, 0.01));
        expect(find.text(profile.customTitle!), findsNothing);
        expect(tester.takeException(), isNull);
        await _save(
          tester,
          'identity-${large ? 'large' : 'normal'}-without-title',
        );
      },
    );
  }

  testWidgets('numeric username and group share a row above the title', (
    tester,
  ) async {
    final profile = _profile(
      false,
      displayName: '2834758851',
      userId: '597454',
      groupName: '百合花蕾',
      customTitle: '把喜欢的故事留在日常里',
      isOnline: false,
    );
    await _pump(
      tester,
      AppThemeFamily.warmPaper,
      Brightness.light,
      profile: profile,
    );
    final identity = find.byKey(const Key('user-profile-identity'));
    final name = find.byKey(const Key('user-profile-name'));
    final group = find.descendant(
      of: identity,
      matching: find.text(profile.groupName!),
    );
    final title = find.byKey(const Key('user-profile-custom-title'));
    expect(tester.getCenter(name).dy, closeTo(tester.getCenter(group).dy, 0.5));
    expect(
      tester.getTopLeft(group).dx,
      greaterThan(tester.getTopRight(name).dx),
    );
    for (final field in [name, group]) {
      expect(
        tester.getTopLeft(title).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(field).dy),
      );
    }
    final l10n = AppLocalizations.of(tester.element(identity));
    expect(find.text(l10n.profileUid('597454')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _save(tester, 'identity-numeric-name');
  });

  testWidgets('long custom title truncates and exposes its full text', (
    tester,
  ) async {
    const customTitle = '把喜欢的故事留在温柔的日常里愿每一次相遇都留下温暖明亮的回声';
    await _pump(
      tester,
      AppThemeFamily.warmPaper,
      Brightness.light,
      profile: _profile(false, customTitle: customTitle, isOnline: false),
    );
    final title = find.byKey(const Key('user-profile-custom-title'));
    final text = tester.widget<Text>(title);
    expect(text.data, customTitle);
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(
      tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
      isTrue,
    );
    await _save(tester, 'identity-long-title');
    await tester.longPress(title);
    await tester.pumpAndSettle();
    expect(find.text(customTitle), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  for (final large in [false, true]) {
    testWidgets(
      'long identity fields stay bounded and keep UID accessible, large=$large',
      (tester) async {
        const userId = '123456789012345678901234567890';
        const displayName = '很长的用户名在窄屏下仍应保留可读身份和复制按钮';
        const groupName = '这是服务器返回的很长用户组名称需要安全显示';
        await _pump(
          tester,
          AppThemeFamily.moonWhite,
          Brightness.light,
          large: large,
          profile: _profile(
            false,
            userId: userId,
            displayName: displayName,
            groupName: groupName,
          ),
        );
        final identity = find.byKey(const Key('user-profile-identity'));
        final name = find.byKey(const Key('user-profile-name'));
        final copyUid = find.byKey(const Key('user-profile-copy-uid'));
        final group = find.descendant(
          of: identity,
          matching: find.text(groupName),
        );
        final l10n = AppLocalizations.of(tester.element(identity));
        expect(tester.widget<Text>(name).data, displayName);
        expect(find.text(l10n.profileUid(userId)), findsOneWidget);
        expect(group, findsOneWidget);
        final card = tester.getRect(identity);
        for (final field in [name, copyUid, group]) {
          final bounds = tester.getRect(field);
          expect(bounds.left, greaterThanOrEqualTo(card.left));
          expect(bounds.right, lessThanOrEqualTo(card.right));
          expect(bounds.bottom, lessThanOrEqualTo(card.bottom));
        }
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(copyUid);
        await tester.pumpAndSettle();
        expect(copyUid.hitTestable(), findsOneWidget);
        expect(tester.widget<TextButton>(copyUid).onPressed, isNotNull);
        await _save(
          tester,
          'identity-long-fields-${large ? 'large' : 'normal'}',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('system bold and text spacing keep identity fields bounded', (
    tester,
  ) async {
    const groupName = '活跃的百合花蕾会员';
    await _pump(
      tester,
      AppThemeFamily.warmPaper,
      Brightness.light,
      width: 330,
      boldText: true,
      letterSpacing: 8,
      wordSpacing: 8,
      profile: _profile(false, groupName: groupName),
    );
    final identity = find.byKey(const Key('user-profile-identity'));
    final card = tester.getRect(identity);
    for (final field in [
      find.byKey(const Key('user-profile-name')),
      find.byKey(const Key('user-profile-copy-uid')),
      find.descendant(of: identity, matching: find.text(groupName)),
      find.byKey(const Key('user-profile-custom-title')),
    ]) {
      final bounds = tester.getRect(field);
      expect(bounds.left, greaterThanOrEqualTo(card.left));
      expect(bounds.right, lessThanOrEqualTo(card.right));
    }
    expect(tester.takeException(), isNull);
    await _save(tester, 'identity-system-text-spacing');
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
              body: ProfilePageBody(
                child: ProfileContent(
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
  ForumUserProfileData? profile,
  ForumUserProfileReadCapabilities? capabilities,
  ForumUserProfileRepository? repository,
  bool settle = true,
  bool disableAnimations = false,
  bool boldText = false,
  double? letterSpacing,
  double? wordSpacing,
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
        verifiedSessionOwnerProvider.overrideWith(
          (ref) => ref.watch(_ownerSource),
        ),
        forumUserProfileRepositoryProvider.overrideWithValue(
          repository ??
              _Repository(
                profile ?? _profile(self),
                capabilities: capabilities,
              ),
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
            data: MediaQuery.of(context)
                .copyWith(
                  textScaler: TextScaler.linear(large ? 2 : 1),
                  boldText: boldText,
                  disableAnimations: disableAnimations,
                )
                .applyTextStyleOverrides(
                  lineHeightScaleFactorOverride: null,
                  letterSpacingOverride: letterSpacing,
                  wordSpacingOverride: wordSpacing,
                  paragraphSpacingOverride: null,
                ),
            child: child!,
          ),
          home: self
              ? const MyProfilePage()
              : UserProfilePage(uid: profile?.identity.userId ?? '8'),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

final _capabilities = ForumUserProfileReadCapabilities(
  values: DataCapabilitySet.from(supported: ForumUserProfileCapability.values),
);

ForumUserProfileData _profile(
  bool self, {
  String? signatureHtml,
  String? customTitle = '在故事与日常之间',
  String? displayName = '夏日回声',
  String? groupName = '普通会员',
  String? userId,
  bool? isOnline = true,
  List<ForumUserProfileMetric>? metrics,
  List<ForumUserProfileActionKind>? actions,
}) => ForumUserProfileData(
  identity: ProfileUserIdentity(
    userId: userId ?? (self ? '101' : '8'),
    displayName: displayName,
  ),
  viewerUserId: '101',
  groupName: groupName,
  customTitle: customTitle,
  isOnline: isOnline,
  metrics:
      metrics ??
      const [
        ForumUserProfileMetric(label: '总积分', value: '2048'),
        ForumUserProfileMetric(label: '积分', value: '1900 点'),
        ForumUserProfileMetric(label: '对象', value: '128'),
      ],
  signatureHtml: signatureHtml ?? '<p>把喜欢的故事，留在温柔的日常里。</p>',
  details: [
    ForumUserProfileDetail(
      label: 'UID',
      value: userId ?? (self ? '101' : '8'),
      section: ForumUserProfileDetailSection.account,
    ),
    if (groupName != null)
      ForumUserProfileDetail(
        label: '用户组',
        value: groupName,
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
  actions:
      actions ??
      (self
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
            ]),
);

class _Repository implements ForumUserProfileRepository {
  _Repository(this.data, {ForumUserProfileReadCapabilities? capabilities})
    : readCapabilities = capabilities ?? _capabilities;
  final ForumUserProfileData data;
  final ForumUserProfileReadCapabilities readCapabilities;
  @override
  ForumUserProfileSourceCapabilities get capabilities =>
      ForumUserProfileSourceCapabilities(values: readCapabilities.values);
  @override
  Future<DataReadResult<ForumUserProfileData, ForumUserProfileReadCapabilities>>
  load(
    ForumUserProfileQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    ForumRequestCancellation? cancellation,
  }) async => DataReadSuccess(
    data: data,
    capabilities: readCapabilities,
    metadata: const DataReadMetadata.network(),
  );
}

typedef _ProfileReadResult =
    DataReadResult<ForumUserProfileData, ForumUserProfileReadCapabilities>;

class _ControlledRepository implements ForumUserProfileRepository {
  final requests = <Completer<_ProfileReadResult>>[];

  @override
  ForumUserProfileSourceCapabilities get capabilities =>
      ForumUserProfileSourceCapabilities(values: _capabilities.values);

  @override
  Future<_ProfileReadResult> load(
    ForumUserProfileQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    ForumRequestCancellation? cancellation,
  }) {
    final completion = Completer<_ProfileReadResult>();
    requests.add(completion);
    return completion.future;
  }

  void complete(ForumUserProfileData data) => requests.last.complete(
    DataReadSuccess(
      data: data,
      capabilities: _capabilities,
      metadata: const DataReadMetadata.network(),
    ),
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
