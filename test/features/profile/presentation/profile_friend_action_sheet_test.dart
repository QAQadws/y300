import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/profile_friend_action_sheet.dart';
import 'package:y300/features/auth/application/verified_session_owner.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../test_support/localized_test_app.dart';
import '../test_support/profile_friend_operation_fixture.dart';

const _output = String.fromEnvironment('PROFILE_VISUAL_OUTPUT');
const _font = String.fromEnvironment('PROFILE_VISUAL_FONT');
const _capture = Key('profile-friend-visual-capture');

void main() {
  setUpAll(() async {
    if (_output.isEmpty) return;
    if (_font.isNotEmpty) {
      await (FontLoader(
        'ProfileFriendVisual',
      )..addFont(File(_font).readAsBytes().then(ByteData.sublistView))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets('request edits server groups and closes only after applied', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = ProfileFriendOperationFixture();
    final results = <bool>[];
    await _pump(tester, service, onResult: results.add);
    await tester.tap(find.byKey(const Key('open-friend-action')));
    await tester.pump();
    expect(service.preparations, hasLength(1));
    expect(service.submissions, isEmpty);
    service.prepared();
    await tester.pumpAndSettle();
    expect(find.text('同好'), findsOneWidget);
    await _save(tester, 'friend-request-sheet');
    await tester.enterText(find.byKey(const Key('profile-friend-note')), '你好');
    await tester.tap(find.byKey(const Key('profile-friend-submit')));
    await tester.pump();
    expect(service.submissions.single.submission.note, '你好');
    expect(service.submissions.single.submission.groupId, '2');
    expect(results, isEmpty);
    expect(find.byType(ProfileFriendActionSheet), findsOneWidget);
    service.applied();
    await tester.pumpAndSettle();
    expect(results, [true]);
    expect(find.byType(ProfileFriendActionSheet), findsNothing);
  });

  testWidgets('unknown preserves input and cannot replay raw server data', (
    tester,
  ) async {
    final service = ProfileFriendOperationFixture();
    final results = <bool>[];
    await _pump(tester, service, onResult: results.add);
    await tester.tap(find.byKey(const Key('open-friend-action')));
    await tester.pump();
    service.prepared();
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ProfileFriendActionSheet)),
    );
    await tester.enterText(
      find.byKey(const Key('profile-friend-note')),
      '保留输入',
    );
    await tester.tap(find.byKey(const Key('profile-friend-submit')));
    await tester.pump();
    service.submissions.single.result.complete(
      const DataCommandOutcomeUnknown(profileFriendWriteFailure),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.profileFriendOperationUnknown), findsOneWidget);
    expect(find.text('保留输入'), findsOneWidget);
    expect(find.textContaining('untrusted server response'), findsNothing);
    expect(find.byKey(const Key('profile-friend-submit')), findsNothing);
    expect(find.byKey(const Key('profile-friend-retry')), findsNothing);
    expect(find.byKey(const Key('profile-friend-open-forum')), findsNothing);
    expect(results, isEmpty);
    await tester.tap(find.text(l10n.commonClose));
    await tester.pumpAndSettle();
    expect(results, [false]);
    expect(service.submissions, hasLength(1));
  });

  testWidgets('narrow enlarged request and removal remain usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final remove in [false, true]) {
      final service = ProfileFriendOperationFixture();
      await _pump(tester, service, remove: remove, textScale: 2);
      await tester.tap(find.byKey(const Key('open-friend-action')));
      await tester.pump();
      service.prepared();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _save(
        tester,
        'friend-${remove ? 'remove' : 'request'}-large-sheet',
      );
      final submit = find.byKey(const Key('profile-friend-submit'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      service.applied();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('owner revision change hides prepared private values', (
    tester,
  ) async {
    final service = ProfileFriendOperationFixture();
    VerifiedSessionOwner? owner = (uid: '101', revision: 0);
    await _pump(tester, service, currentOwner: () => owner);
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('open-friend-action'))),
    );
    await tester.tap(find.byKey(const Key('open-friend-action')));
    await tester.pump();
    service.prepared();
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('profile-friend-note')),
      '私密输入',
    );
    owner = (uid: '101', revision: 1);
    container.invalidate(verifiedSessionOwnerProvider);
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ProfileFriendActionSheet)),
    );
    expect(find.text(l10n.profileLoginRequired), findsOneWidget);
    expect(find.byKey(const Key('profile-friend-note')), findsNothing);
    expect(find.byKey(const Key('profile-friend-submit')), findsNothing);
    expect(service.submissions, isEmpty);
  });
}

Future<void> _pump(
  WidgetTester tester,
  ProfileFriendOperationFixture service, {
  bool remove = false,
  double textScale = 1,
  void Function(bool)? onResult,
  VerifiedSessionOwner? Function()? currentOwner,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        forumFriendOperationsProvider.overrideWithValue(service),
        verifiedSessionOwnerProvider.overrideWith(
          (_) =>
              currentOwner == null ? (uid: '101', revision: 0) : currentOwner(),
        ),
      ],
      child: RepaintBoundary(
        key: _capture,
        child: LocalizedTestApp(
          debugShowCheckedModeBanner: false,
          theme: _font.isEmpty
              ? AppTheme.light()
              : AppTheme.light().copyWith(
                  textTheme: AppTheme.light().textTheme.apply(
                    fontFamily: 'ProfileFriendVisual',
                  ),
                ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                key: const Key('open-friend-action'),
                onPressed: () async {
                  final result = await showProfileFriendAction(
                    context: context,
                    ref: ref,
                    targetUserId: '202',
                    actionLink: profileFriendLink(remove: remove),
                  );
                  onResult?.call(result);
                },
                child: const Text('open fixture'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester, String name) async {
  if (_output.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(_output).create(recursive: true);
      await File(
        '$_output/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
