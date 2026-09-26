import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/more/presentation/more_account_avatar.dart';
import 'package:y300/features/more/presentation/more_account_header.dart';
import 'package:y300/features/more/presentation/more_account_action.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';
import 'package:y300/features/profile/presentation/current_account_summary_controller.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_default_avatar.dart';

import '../../../test_support/localized_test_app.dart';

const _owner = (uid: '42', revision: 1);
const _session = AuthSessionViewState(
  isLoggedIn: true,
  uid: '42',
  username: 'Session reader',
  isLoggingOut: false,
);
final _ownerSource = StateProvider<VerifiedProfileOwner?>((ref) => _owner);
final _sessionSource = StateProvider<AuthSessionViewState>((ref) => _session);

void main() {
  testWidgets(
    'numeric refresh keeps the counter state and uses the shared animation duration',
    (tester) async {
      final repository = _Repository(
        (read) async => _success(credits: read == 1 ? 12 : 19),
      );
      await _pumpHeader(tester, repository: repository);
      final counter = find.descendant(
        of: find.byKey(const Key('more-account-credits')),
        matching: find.byType(AnimatedFlipCounter),
      );
      final initialState = tester.element(counter);
      expect(tester.widget<AnimatedFlipCounter>(counter).value, 12);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MoreAccountHeader)),
      );
      await container
          .read(currentAccountSummaryControllerProvider.notifier)
          .refresh();
      await tester.pump();
      expect(tester.element(counter), same(initialState));
      expect(tester.widget<AnimatedFlipCounter>(counter).value, 19);
      expect(
        tester.widget<AnimatedFlipCounter>(counter).duration,
        const Duration(milliseconds: 260),
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('reduced motion disables counter and identity transitions', (
    tester,
  ) async {
    await _pumpHeader(
      tester,
      repository: _Repository((_) async => _success()),
      disableAnimations: true,
    );
    for (final counter in tester.widgetList<AnimatedFlipCounter>(
      find.byType(AnimatedFlipCounter),
    )) {
      expect(counter.duration, Duration.zero);
      expect(counter.negativeSignDuration, Duration.zero);
    }
    for (final transition in tester.widgetList<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher),
    )) {
      expect(transition.duration, Duration.zero);
    }
  });
  testWidgets('signed account shows structured summary and separate actions', (
    tester,
  ) async {
    var loginCount = 0;
    var logoutCount = 0;
    var profileCount = 0;
    final repository = _Repository((_) async => _success());
    await _pumpHeader(
      tester,
      repository: repository,
      onLogin: () => loginCount++,
      onLogout: () => logoutCount++,
      onOpenProfile: () => profileCount++,
    );
    final l10n = _l10n(tester);

    expect(find.text('Profile reader'), findsOneWidget);
    expect(find.text('Fixture readers'), findsOneWidget);
    expect(_statistic('credits', '12'), findsOneWidget);
    expect(_statistic('threads', '3'), findsOneWidget);
    expect(_statistic('replies', '7'), findsOneWidget);
    expect(find.text(l10n.moreAccountThreads), findsOneWidget);
    expect(find.text(l10n.moreAccountReplies), findsOneWidget);
    expect(find.text(l10n.moreAccountCreditLabel), findsOneWidget);
    _expectAccountLayout(tester);
    expect(
      tester.getCenter(find.byKey(const Key('more-account-threads'))).dx,
      lessThan(
        tester.getCenter(find.byKey(const Key('more-account-replies'))).dx,
      ),
    );
    expect(
      tester.getCenter(find.byKey(const Key('more-account-replies'))).dx,
      lessThan(
        tester.getCenter(find.byKey(const Key('more-account-credits'))).dx,
      ),
    );
    expect(find.byKey(const Key('more-logout-entry')), findsOneWidget);
    expect(_logoutButton(tester).tooltip, l10n.moreLogout);
    expect(find.byTooltip(l10n.moreLogout), findsOneWidget);
    expect(find.text(l10n.moreLogout), findsNothing);
    expect(find.byIcon(Icons.logout), findsOneWidget);
    expect(find.byKey(const Key('more-login-entry')), findsNothing);
    expect(repository.reads, 1);
    expect(repository.policies, [CacheLoadPolicy.networkFirst]);

    final avatar = tester.widget<MoreAccountAvatar>(
      find.byType(MoreAccountAvatar),
    );
    expect(avatar.uid, _owner.uid);
    _expectDefaultAvatar(tester);

    await tester.tap(find.byKey(const Key('more-account-avatar')));
    await tester.tap(find.byKey(const Key('more-account-name')));
    await tester.tap(find.byKey(const Key('more-logout-entry')));
    expect(profileCount, 2);
    expect(logoutCount, 1);
    expect(loginCount, 0);
    await tester.pump();
    expect(repository.reads, 1);
  });

  testWidgets('guest has a login action and no account summary request', (
    tester,
  ) async {
    var loginCount = 0;
    var profileCount = 0;
    final repository = _Repository((_) async => _success());
    await _pumpHeader(
      tester,
      repository: repository,
      owner: null,
      session: const AuthSessionViewState.signedOut(),
      onLogin: () => loginCount++,
      onOpenProfile: () => profileCount++,
    );

    expect(find.text(_l10n(tester).moreAccountSignedOut), findsOneWidget);
    expect(find.byKey(const Key('more-account-credits')), findsNothing);
    expect(find.byKey(const Key('more-account-group')), findsNothing);
    expect(find.byKey(const Key('more-logout-entry')), findsNothing);
    expect(find.text(_l10n(tester).moreLogin), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('more-login-entry')))
          .onPressed,
      isNotNull,
    );
    expect(repository.reads, 0);
    _expectDefaultAvatar(tester);

    await tester.tap(find.byKey(const Key('more-login-entry')));
    expect(loginCount, 1);
    expect(
      tester.widget<InkWell>(find.byKey(const Key('more-account-name'))).onTap,
      isNull,
    );
    expect(profileCount, 0);
  });

  testWidgets('unverified signed session shows checking and disables actions', (
    tester,
  ) async {
    final repository = _Repository((_) async => _success());
    await _pumpHeader(
      tester,
      repository: repository,
      owner: null,
      settle: false,
    );
    await tester.pump();

    expect(find.text(_l10n(tester).moreAccountChecking), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byKey(const Key('more-account-credits')), findsNothing);
    expect(_logoutButton(tester).onPressed, isNull);
    expect(repository.reads, 0);
  });

  testWidgets(
    'summary loads silently while preserving the session name and unknown totals',
    (tester) async {
      final pending = Completer<_ReadResult>();
      final repository = _Repository((_) => pending.future);
      await _pumpHeader(tester, repository: repository, settle: false);
      await tester.pump();
      final l10n = _l10n(tester);

      expect(find.text(_session.username), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text(l10n.moreAccountUnavailable), findsNWidgets(3));
      expect(find.byKey(const Key('more-account-group')), findsNothing);
      expect(repository.reads, 1);

      pending.complete(_success());
      await tester.pumpAndSettle();
      expect(find.text('Profile reader'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'missing capabilities hide group and avatar and leave total unknown',
    (tester) async {
      final repository = _Repository(
        (_) async => _success(
          avatarUrl: 'https://example.test/private-avatar.png',
          capabilities: CurrentUserProfileReadCapabilities(
            values: DataCapabilitySet.supported([
              CurrentUserProfileCapability.stableUserIdentity,
              CurrentUserProfileCapability.userName,
            ]),
          ),
        ),
      );
      await _pumpHeader(tester, repository: repository);
      final l10n = _l10n(tester);

      expect(find.byKey(const Key('more-account-group')), findsNothing);
      expect(find.text(l10n.moreAccountUnavailable), findsNWidgets(3));
      _expectDefaultAvatar(tester);
    },
  );

  for (final credits in [0, -7]) {
    testWidgets('credit total $credits stays visible without fallback', (
      tester,
    ) async {
      await _pumpHeader(
        tester,
        repository: _Repository((_) async => _success(credits: credits)),
      );

      expect(_statistic('credits', credits.toString()), findsOneWidget);
    });
  }

  testWidgets('failed summary offers a localized retry that recovers', (
    tester,
  ) async {
    final repository = _Repository(
      (read) async => read == 1
          ? const DataReadFailure(
              kind: DataReadFailureKind.network,
              diagnosticMessage: 'private synthetic server payload',
            )
          : _success(),
    );
    await _pumpHeader(tester, repository: repository);

    expect(find.text(_l10n(tester).moreAccountLoadFailed), findsOneWidget);
    expect(find.text('private synthetic server payload'), findsNothing);
    expect(find.text(_session.username), findsOneWidget);
    await tester.tap(find.byKey(const Key('more-account-retry')));
    await tester.pumpAndSettle();

    expect(repository.reads, 2);
    expect(find.text('Profile reader'), findsOneWidget);
    expect(find.byKey(const Key('more-account-retry')), findsNothing);
  });

  testWidgets('logout immediately removes the old summary', (tester) async {
    final repository = _Repository((_) async => _success());
    await _pumpHeader(tester, repository: repository);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MoreAccountHeader)),
    );

    container.read(_ownerSource.notifier).state = null;
    container.read(_sessionSource.notifier).state =
        const AuthSessionViewState.signedOut();
    await tester.pumpAndSettle();

    expect(find.text('Profile reader'), findsNothing);
    expect(find.text('Fixture readers'), findsNothing);
    expect(find.byKey(const Key('more-account-credits')), findsNothing);
    expect(find.text(_l10n(tester).moreAccountSignedOut), findsOneWidget);
    expect(repository.reads, 1);
  });

  testWidgets(
    'pending account navigation disables both account and profile taps',
    (tester) async {
      await _pumpHeader(
        tester,
        repository: _Repository((_) async => _success()),
        pendingAction: true,
        settle: false,
      );
      await tester.pump();

      expect(_logoutButton(tester).onPressed, isNull);
      expect(_logoutButton(tester).tooltip, _l10n(tester).moreLogout);
      expect(find.text(_l10n(tester).moreLogout), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('more-logout-entry')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
      expect(
        tester
            .widget<InkWell>(find.byKey(const Key('more-account-avatar')))
            .onTap,
        isNull,
      );
      expect(
        tester
            .widget<InkWell>(find.byKey(const Key('more-account-name')))
            .onTap,
        isNull,
      );
    },
  );

  for (final family in AppThemeFamily.values) {
    testWidgets(
      'account header stays transparent with $family dark group colors',
      (tester) async {
        final theme = AppTheme.build(
          family: family,
          brightness: Brightness.dark,
        );
        await _pumpHeader(
          tester,
          repository: _Repository((_) async => _success()),
          theme: theme,
        );
        final material = tester.widget<Material>(
          find
              .descendant(
                of: find.byKey(const Key('more-account-header')),
                matching: find.byType(Material),
              )
              .first,
        );
        final group = tester.widget<Container>(
          find.byKey(const Key('more-account-group')),
        );

        expect(material.color, Colors.transparent);
        expect(material.surfaceTintColor, Colors.transparent);
        expect(material.shape, theme.cardTheme.shape);
        expect(
          (group.decoration as BoxDecoration).color,
          theme.colorScheme.secondaryContainer,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('300dp Traditional header fits 2x text and long account values', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(300, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const name = 'Very long fixture nickname 百合讀者的很長暱稱';
    const group = 'Very long fixture group 百合論壇的很長使用者群組';
    const credits = 9223372036854775807;
    await _pumpHeader(
      tester,
      repository: _Repository(
        (_) async => _success(name: name, group: group, credits: credits),
      ),
      locale: const Locale('zh', 'TW'),
      textScale: 2,
    );

    expect(find.text(name), findsOneWidget);
    expect(find.text(group), findsOneWidget);
    expect(_statistic('credits', '$credits'), findsOneWidget);
    expect(find.byKey(const Key('more-logout-entry')), findsOneWidget);
    expect(_logoutButton(tester).tooltip, _l10n(tester).moreLogout);
    expect(find.text(_l10n(tester).moreLogout), findsNothing);
    _expectAccountLayout(tester, groupWraps: true);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpHeader(
  WidgetTester tester, {
  required _Repository repository,
  VerifiedProfileOwner? owner = _owner,
  AuthSessionViewState session = _session,
  VoidCallback? onLogin,
  VoidCallback? onLogout,
  VoidCallback? onOpenProfile,
  bool pendingAction = false,
  bool settle = true,
  ThemeData? theme,
  Locale locale = const Locale('zh'),
  double textScale = 1,
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        imageCacheServiceProvider.overrideWithValue(_NoAvatarCache()),
        _ownerSource.overrideWith((ref) => owner),
        _sessionSource.overrideWith((ref) => session),
        verifiedProfileOwnerProvider.overrideWith(
          (ref) => ref.watch(_ownerSource),
        ),
        authSessionControllerProvider.overrideWith(_TestAuthController.new),
        currentAccountSummaryRepositoryProvider.overrideWithValue(repository),
      ],
      child: LocalizedTestApp(
        locale: locale,
        theme: theme ?? AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: child!,
        ),
        home: Scaffold(
          appBar: AppBar(
            actions: [
              MoreAccountAction(
                onLogin: onLogin ?? () {},
                onLogout: onLogout ?? () {},
                isPending: pendingAction,
              ),
            ],
          ),
          body: ListView(
            children: [
              MoreAccountHeader(
                onOpenProfile: onOpenProfile ?? () {},
                isAccountActionPending: pendingAction,
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(MoreAccountHeader)));

IconButton _logoutButton(WidgetTester tester) =>
    tester.widget<IconButton>(find.byKey(const Key('more-logout-entry')));

Finder _statistic(String name, String value) {
  final counters = find.descendant(
    of: find.byKey(Key('more-account-$name')),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is AnimatedFlipCounter && widget.value.toString() == value,
    ),
  );
  if (counters.evaluate().isNotEmpty) return counters;
  return find.descendant(
    of: find.byKey(Key('more-account-$name')),
    matching: find.text(value),
  );
}

void _expectAccountLayout(WidgetTester tester, {bool groupWraps = false}) {
  final avatar = tester.getRect(find.byKey(const Key('more-account-avatar')));
  final name = tester.getRect(find.byKey(const Key('more-account-name')));
  final group = tester.getRect(find.byKey(const Key('more-account-group')));

  expect(name.top, greaterThan(avatar.bottom));
  expect(name.left, avatar.left);
  if (groupWraps) {
    expect(group.top, greaterThan(name.bottom));
    expect(group.left, avatar.left);
  } else {
    expect(group.left, greaterThan(name.right));
    expect(group.center.dy, closeTo(name.center.dy, 0.1));
  }
  for (final statistic in ['threads', 'replies', 'credits']) {
    final rect = tester.getRect(find.byKey(Key('more-account-$statistic')));
    expect(rect.left, greaterThan(avatar.right));
    expect(rect.bottom, closeTo(avatar.bottom, 0.1));
    final label = find
        .descendant(
          of: find.byKey(Key('more-account-$statistic')),
          matching: find.byType(Text),
        )
        .last;
    expect(tester.getRect(label).bottom, closeTo(avatar.bottom, 0.1));
  }
}

void _expectDefaultAvatar(WidgetTester tester) {
  final images = find.byWidgetPredicate(
    (widget) =>
        widget is Image &&
        widget.image is AssetImage &&
        (widget.image as AssetImage).assetName == forumDefaultAvatarAsset,
  );
  expect(images, findsOneWidget);
}

class _TestAuthController extends AuthSessionController {
  @override
  Future<AuthSessionViewState> build() async => ref.watch(_sessionSource);
}

typedef _ReadResult =
    DataReadResult<CurrentUserProfileData, CurrentUserProfileReadCapabilities>;

_ReadResult _success({
  String name = 'Profile reader',
  String group = 'Fixture readers',
  int credits = 12,
  String? avatarUrl,
  CurrentUserProfileReadCapabilities? capabilities,
}) => DataReadSuccess(
  data: CurrentUserProfileData(
    identity: ProfileUserIdentity(userId: _owner.uid, displayName: name),
    avatarUrl: avatarUrl,
    groupId: '10',
    groupName: group,
    creditTotal: credits,
    threadCount: 3,
    replyCount: 7,
  ),
  capabilities:
      capabilities ??
      CurrentUserProfileReadCapabilities(
        values: DataCapabilitySet.supported(
          CurrentUserProfileCapability.values,
        ),
      ),
  metadata: const DataReadMetadata.network(),
);

final class _Repository implements CurrentAccountSummaryRepository {
  _Repository(this.onRead);

  final Future<_ReadResult> Function(int read) onRead;
  int reads = 0;
  final List<CacheLoadPolicy> policies = [];

  @override
  CurrentUserProfileSourceCapabilities get capabilities =>
      CurrentUserProfileSourceCapabilities(
        values: DataCapabilitySet.supported(
          CurrentUserProfileCapability.values,
        ),
      );

  @override
  Future<_ReadResult> load(
    CurrentAccountSummaryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) {
    policies.add(cachePolicy);
    return onRead(++reads);
  }
}

class _NoAvatarCache extends Fake implements ImageCacheService {
  @override
  Future<CachedImageResult?> getCached(String key) async => null;
}
