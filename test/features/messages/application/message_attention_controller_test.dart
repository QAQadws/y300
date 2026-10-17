import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/messages/application/message_attention_controller.dart';

const _unknown = ForumMessageAttentionState.unknown;
const _absent = ForumMessageAttentionState.absent;
const _present = ForumMessageAttentionState.present;
const _owner = (sessionOwner: (uid: '42', revision: 1), sourceGeneration: 3);

ForumMessageAttentionObservation _categories({
  ForumMessageAttentionState privateMessages = _unknown,
  ForumMessageAttentionState notifications = _unknown,
  int? count,
  ForumMessageAttentionSource source = ForumMessageAttentionSource.api,
  String viewer = '42',
}) => ForumMessageAttentionObservation(
  viewerUserId: viewer,
  source: source,
  privateMessages: privateMessages,
  notifications: notifications,
  notificationCount: count,
);

ForumMessageAttentionObservation _mobile(ForumMessageAttentionState hint) =>
    ForumMessageAttentionObservation(
      viewerUserId: '42',
      source: ForumMessageAttentionSource.mobileHtml,
      combinedHint: hint,
    );

void main() {
  late MessageAttentionController controller;

  void accept(ForumMessageAttentionObservation observation, [int? sequence]) {
    controller.accept(
      observation,
      owner: _owner,
      sequence: sequence ?? controller.nextRequestSequence(),
    );
  }

  setUp(() {
    controller = MessageAttentionController()..setOwner(_owner);
  });
  tearDown(() => controller.dispose());

  test('unknown initial evidence has no projected dots', () {
    accept(_categories());
    expect(controller.value.combined, _unknown);
    expect(controller.value.attentionEpoch, 0);
    final projected = controller.value.project(messagesVisible: false);
    expect(projected.messagesNavigationDot, isFalse);
    expect(projected.moreNavigationDot, isFalse);
    expect(projected.myMessagesDot, isFalse);
  });

  test('mobile positive stays combined-only and projects hidden messages', () {
    accept(_mobile(_present));
    expect(controller.value.privateMessages, _unknown);
    expect(controller.value.notifications, _unknown);
    expect(controller.value.notificationCount, isNull);
    expect(controller.value.attentionEpoch, 1);
    final projected = controller.value.project(messagesVisible: false);
    expect(projected.messagesNavigationDot, isFalse);
    expect(projected.moreNavigationDot, isTrue);
    expect(projected.myMessagesDot, isTrue);
  });

  test('visible messages own the only dot without changing the round', () {
    accept(_mobile(_present));
    final projected = controller.value.project(messagesVisible: true);
    expect(projected.messagesNavigationDot, isTrue);
    expect(projected.moreNavigationDot, isFalse);
    expect(projected.myMessagesDot, isFalse);
    expect(controller.value.attentionEpoch, 1);
  });

  test('only actual More visibility acknowledges its navigation dot', () {
    accept(_mobile(_present));
    controller.setMoreVisible(false);
    expect(controller.value.hasUnacknowledgedAttention, isTrue);
    controller.setMoreVisible(true);
    expect(controller.value.acknowledgedMoreEpoch, 1);
    expect(
      controller.value.project(messagesVisible: false).moreNavigationDot,
      isFalse,
    );
    expect(
      controller.value.project(messagesVisible: false).myMessagesDot,
      isTrue,
    );
  });

  test('same-round positive responses never resurrect acknowledged More', () {
    accept(_mobile(_present));
    controller.setMoreVisible(true);
    controller.setMoreVisible(false);
    accept(_mobile(_present));
    accept(_categories());
    accept(_categories(privateMessages: _present));
    expect(controller.value.attentionEpoch, 1);
    expect(controller.value.acknowledgedMoreEpoch, 1);
    expect(controller.value.hasUnacknowledgedAttention, isFalse);
  });

  test('source upgrade and newly known category do not create arrivals', () {
    accept(_mobile(_present));
    controller.acknowledgeMore();
    accept(_categories(privateMessages: _present));
    accept(
      _categories(
        privateMessages: _present,
        notifications: _absent,
        count: 0,
        source: ForumMessageAttentionSource.desktopHtml,
      ),
    );
    expect(controller.value.attentionEpoch, 1);
    expect(controller.value.hasUnacknowledgedAttention, isFalse);
  });

  test('partial unknown never clears another category or its count', () {
    accept(_categories(notifications: _present, count: 4));
    accept(_categories(privateMessages: _absent));
    expect(controller.value.privateMessages, _absent);
    expect(controller.value.notifications, _present);
    expect(controller.value.notificationCount, 4);
    expect(controller.value.combined, _present);
    expect(controller.value.attentionEpoch, 1);
  });

  test('partial negative cannot erase a mobile aggregate positive', () {
    accept(_mobile(_present));
    accept(_categories(notifications: _absent, count: 0));
    expect(controller.value.combined, _present);
    expect(controller.value.privateMessages, _unknown);
    expect(controller.value.attentionEpoch, 1);
  });

  test('complete newer categories retire a historical mobile positive', () {
    accept(_mobile(_present));
    controller.acknowledgeMore();
    accept(
      _categories(privateMessages: _absent, notifications: _absent, count: 0),
    );
    expect(controller.value.combined, _absent);
    expect(controller.value.hasAttention, isFalse);
    expect(controller.value.attentionEpoch, 1);
    accept(_mobile(_present));
    expect(controller.value.attentionEpoch, 2);
    expect(controller.value.hasUnacknowledgedAttention, isTrue);
  });

  test('separate newer negative categories together retire the aggregate', () {
    accept(_mobile(_present), 10);
    accept(_categories(notifications: _absent, count: 0), 20);
    expect(controller.value.combined, _present);
    accept(_categories(privateMessages: _absent), 15);
    expect(controller.value.combined, _absent);
  });

  test(
    'explicit category false-to-true creates a round during other hints',
    () {
      accept(
        _categories(
          privateMessages: _present,
          notifications: _absent,
          count: 0,
        ),
      );
      controller.acknowledgeMore();
      accept(_categories(notifications: _present, count: 1));
      expect(controller.value.combined, _present);
      expect(controller.value.attentionEpoch, 2);
      expect(controller.value.hasUnacknowledgedAttention, isTrue);
    },
  );

  test('complete same-semantic count growth creates one round', () {
    accept(_categories(notifications: _present, count: 2));
    controller.acknowledgeMore();
    accept(
      _categories(
        notifications: _present,
        count: 3,
        source: ForumMessageAttentionSource.desktopHtml,
      ),
    );
    expect(controller.value.attentionEpoch, 2);
    expect(controller.value.hasUnacknowledgedAttention, isTrue);
    controller.acknowledgeMore();
    accept(_categories(notifications: _present, count: 3));
    expect(controller.value.attentionEpoch, 2);
    expect(controller.value.hasUnacknowledgedAttention, isFalse);
  });

  test('countless known hint breaks the count-growth baseline', () {
    accept(_categories(notifications: _present, count: 2));
    controller.acknowledgeMore();
    accept(_categories(notifications: _present));
    expect(controller.value.notificationCount, isNull);
    accept(_categories(notifications: _present, count: 5));
    expect(controller.value.attentionEpoch, 1);
    expect(controller.value.hasUnacknowledgedAttention, isFalse);
  });

  test(
    'mobile evidence cannot turn restored count knowledge into arrivals',
    () {
      accept(_categories(notifications: _present, count: 2));
      controller.acknowledgeMore();
      accept(_mobile(_present));
      accept(_categories(notifications: _present, count: 5));
      expect(controller.value.attentionEpoch, 1);
      expect(controller.value.hasUnacknowledgedAttention, isFalse);
    },
  );

  test('decreased reliable count becomes the next growth baseline', () {
    accept(_categories(notifications: _present, count: 5));
    controller.acknowledgeMore();
    accept(_categories(notifications: _present, count: 2));
    expect(controller.value.attentionEpoch, 1);
    accept(_categories(notifications: _present, count: 3));
    expect(controller.value.attentionEpoch, 2);
  });

  test('multiple new-arrival facts in one response create only one round', () {
    accept(
      _categories(privateMessages: _absent, notifications: _absent, count: 0),
    );
    accept(
      _categories(privateMessages: _present, notifications: _present, count: 2),
    );
    expect(controller.value.attentionEpoch, 1);
  });

  test('late same-category observation cannot revive cleared hints', () {
    accept(_categories(privateMessages: _absent), 2);
    accept(_categories(privateMessages: _present), 1);
    expect(controller.value.privateMessages, _absent);
    expect(controller.value.hasAttention, isFalse);
  });

  test('late category cannot bypass newer aggregate absence', () {
    accept(_mobile(_absent), 5);
    accept(_categories(notifications: _present, count: 4), 4);
    expect(controller.value.combined, _absent);
    expect(controller.value.notificationCount, isNull);
    expect(controller.value.attentionEpoch, 0);
  });

  test('older aggregate cannot overwrite more recent partial coverage', () {
    accept(_categories(notifications: _present, count: 4), 5);
    accept(_mobile(_absent), 4);
    expect(controller.value.combined, _present);
    expect(controller.value.notificationCount, 4);
  });

  test(
    'late aggregate absence joins newer category absence to clear old hint',
    () {
      accept(_mobile(_present), 10);
      accept(_categories(privateMessages: _absent), 13);
      accept(_mobile(_absent), 12);
      expect(controller.value.combined, _absent);
      expect(controller.value.privateMessages, _absent);
      expect(controller.value.notifications, _unknown);
      expect(controller.value.attentionEpoch, 1);
      accept(_categories(notifications: _present, count: 1), 11);
      expect(controller.value.combined, _absent);
      expect(controller.value.attentionEpoch, 1);
    },
  );

  test(
    'older aggregate absence preserves later positive and its negative baseline',
    () {
      accept(_mobile(_present), 10);
      controller.acknowledgeMore();
      accept(_categories(privateMessages: _present), 13);
      accept(_mobile(_absent), 12);
      expect(controller.value.combined, _present);
      expect(controller.value.privateMessages, _present);
      expect(controller.value.attentionEpoch, 1);
      expect(controller.value.hasUnacknowledgedAttention, isFalse);
      accept(_categories(privateMessages: _absent), 14);
      expect(controller.value.combined, _absent);
      accept(_mobile(_present), 15);
      expect(controller.value.attentionEpoch, 2);
      expect(controller.value.hasUnacknowledgedAttention, isTrue);
    },
  );

  test(
    'late aggregate absence preserves newer notification count coverage',
    () {
      accept(_mobile(_present), 10);
      accept(_categories(notifications: _present, count: 3), 13);
      controller.acknowledgeMore();
      accept(_mobile(_absent), 12);
      expect(controller.value.combined, _present);
      expect(controller.value.notificationCount, 3);
      expect(controller.value.attentionEpoch, 1);
      accept(_categories(notifications: _present, count: 4), 14);
      expect(controller.value.notificationCount, 4);
      expect(controller.value.attentionEpoch, 2);
    },
  );

  test('older aggregate absence never bypasses a newer aggregate positive', () {
    accept(_mobile(_present), 13);
    controller.acknowledgeMore();
    accept(_mobile(_absent), 12);
    expect(controller.value.combined, _present);
    expect(controller.value.attentionEpoch, 1);
    expect(controller.value.hasUnacknowledgedAttention, isFalse);
  });

  test('aggregate source upgrade never recounts older negative categories', () {
    accept(
      _categories(privateMessages: _absent, notifications: _absent, count: 0),
      1,
    );
    accept(_mobile(_present), 2);
    controller.acknowledgeMore();
    expect(controller.value.privateMessages, _unknown);
    expect(controller.value.notifications, _unknown);
    accept(
      _categories(privateMessages: _present, notifications: _absent, count: 0),
      3,
    );
    expect(controller.value.combined, _present);
    expect(controller.value.attentionEpoch, 1);
    expect(controller.value.hasUnacknowledgedAttention, isFalse);
    accept(_categories(notifications: _present, count: 1), 4);
    expect(controller.value.attentionEpoch, 2);
    expect(controller.value.hasUnacknowledgedAttention, isTrue);
  });

  test('unknown newer response does not block older reliable new evidence', () {
    accept(_categories(), 5);
    accept(_categories(notifications: _present, count: 4), 4);
    expect(controller.value.hasAttention, isTrue);
  });

  test(
    'aggregate absence retires old category positives without inventing them',
    () {
      accept(
        _categories(
          privateMessages: _present,
          notifications: _present,
          count: 2,
        ),
      );
      accept(_mobile(_absent));
      expect(controller.value.privateMessages, _unknown);
      expect(controller.value.notifications, _unknown);
      expect(controller.value.combined, _absent);
      accept(_categories(privateMessages: _present));
      expect(controller.value.attentionEpoch, 2);
    },
  );

  test(
    'new observation while More is actually visible is immediately local ack',
    () {
      controller.setMoreVisible(true);
      accept(_mobile(_present));
      expect(controller.value.acknowledgedMoreEpoch, 1);
      expect(controller.value.hasUnacknowledgedAttention, isFalse);
      accept(_categories(notifications: _present, count: 1));
      accept(_categories(notifications: _present, count: 2));
      expect(controller.value.attentionEpoch, 2);
      expect(controller.value.acknowledgedMoreEpoch, 2);
    },
  );

  test('route coverage or background stops automatic acknowledgement', () {
    controller.setMoreVisible(true);
    accept(_mobile(_present));
    controller.setMoreVisible(false);
    accept(_mobile(_absent));
    accept(_mobile(_present));
    expect(controller.value.attentionEpoch, 2);
    expect(controller.value.acknowledgedMoreEpoch, 1);
    expect(controller.value.hasUnacknowledgedAttention, isTrue);
  });

  test('retiring a different shell never retires active More visibility', () {
    final activeShell = Object();
    final hiddenShell = Object();
    controller.setMoreVisible(true, visibilityOwner: activeShell);
    controller.setMoreVisible(false, visibilityOwner: hiddenShell);
    accept(_mobile(_present));
    expect(controller.value.hasUnacknowledgedAttention, isFalse);
    controller.setMoreVisible(false, visibilityOwner: activeShell);
    accept(_mobile(_absent));
    accept(_mobile(_present));
    expect(controller.value.hasUnacknowledgedAttention, isTrue);
  });

  test('navigation configuration changes preserve More acknowledgement', () {
    accept(_mobile(_present));
    controller.acknowledgeMore();
    expect(
      controller.value.project(messagesVisible: true).messagesNavigationDot,
      isTrue,
    );
    expect(
      controller.value.project(messagesVisible: false).moreNavigationDot,
      isFalse,
    );
    expect(controller.value.attentionEpoch, 1);
  });

  test(
    'owner change rejects late observations and resets acknowledgements',
    () {
      accept(_mobile(_present));
      controller.acknowledgeMore();
      const other = (
        sessionOwner: (uid: '99', revision: 1),
        sourceGeneration: 4,
      );
      controller.setOwner(other);
      accept(_mobile(_present));
      expect(controller.value.owner, other);
      expect(controller.value.combined, _unknown);
      expect(controller.value.attentionEpoch, 0);
      expect(controller.value.acknowledgedMoreEpoch, 0);
      controller.accept(
        _categories(viewer: '99', privateMessages: _present),
        owner: other,
        sequence: controller.nextRequestSequence(),
      );
      expect(controller.value.attentionEpoch, 1);
    },
  );

  test('same UID session revision change rejects previous owner', () {
    accept(_mobile(_present));
    const relogin = (
      sessionOwner: (uid: '42', revision: 2),
      sourceGeneration: 3,
    );
    controller.setOwner(relogin);
    accept(_mobile(_present));
    expect(controller.value.combined, _unknown);
    expect(controller.value.attentionEpoch, 0);
  });

  test('source lifetime change rejects same-account late response', () {
    accept(_mobile(_present));
    const replacement = (
      sessionOwner: (uid: '42', revision: 1),
      sourceGeneration: 4,
    );
    controller.setOwner(replacement);
    accept(_mobile(_present));
    expect(controller.value.hasAttention, isFalse);
  });

  test('owner loss clears all old projection and rejects old response', () {
    accept(_mobile(_present));
    controller.setOwner(null);
    accept(_mobile(_present));
    expect(controller.value.owner, isNull);
    expect(controller.value.hasAttention, isFalse);
    expect(controller.value.attentionEpoch, 0);
  });

  test('new owner retains actual More visibility but none of its old ack', () {
    controller.setMoreVisible(true);
    accept(_mobile(_present));
    controller.setOwner(null);
    controller.setOwner(_owner);
    expect(controller.value.acknowledgedMoreEpoch, 0);
    accept(_mobile(_present));
    expect(controller.value.attentionEpoch, 1);
    expect(controller.value.acknowledgedMoreEpoch, 1);
  });

  test('viewer mismatch and invalid request order cannot mutate state', () {
    accept(_categories(privateMessages: _present, viewer: '99'));
    accept(_mobile(_present), 0);
    expect(controller.value.hasAttention, isFalse);
    expect(controller.value.attentionEpoch, 0);
  });

  test(
    'conflicting same-response aggregate and categories retain old state',
    () {
      accept(_mobile(_present));
      final before = controller.value;
      accept(
        const ForumMessageAttentionObservation(
          viewerUserId: '42',
          source: ForumMessageAttentionSource.api,
          privateMessages: _present,
          combinedHint: _absent,
        ),
      );
      expect(controller.value, before);
    },
  );

  test(
    'consistent mixed coverage retains its same-response positive aggregate',
    () {
      accept(
        const ForumMessageAttentionObservation(
          viewerUserId: '42',
          source: ForumMessageAttentionSource.api,
          privateMessages: _absent,
          combinedHint: _present,
        ),
      );
      expect(controller.value.privateMessages, _absent);
      expect(controller.value.notifications, _unknown);
      expect(controller.value.combined, _present);
      expect(controller.value.attentionEpoch, 1);
    },
  );

  test(
    'same-response mixed aggregate preserves its reliable count baseline',
    () {
      accept(
        const ForumMessageAttentionObservation(
          viewerUserId: '42',
          source: ForumMessageAttentionSource.api,
          notifications: _present,
          notificationCount: 4,
          combinedHint: _present,
        ),
      );
      expect(controller.value.notificationCount, 4);
      controller.acknowledgeMore();
      accept(_categories(notifications: _present, count: 5));
      expect(controller.value.notificationCount, 5);
      expect(controller.value.attentionEpoch, 2);
      expect(controller.value.hasUnacknowledgedAttention, isTrue);
    },
  );

  test(
    'same-response mixed absence preserves explicit category and zero count',
    () {
      accept(
        const ForumMessageAttentionObservation(
          viewerUserId: '42',
          source: ForumMessageAttentionSource.api,
          notifications: _absent,
          notificationCount: 0,
          combinedHint: _absent,
        ),
      );
      expect(controller.value.combined, _absent);
      expect(controller.value.notifications, _absent);
      expect(controller.value.notificationCount, 0);
      expect(controller.value.attentionEpoch, 0);
      accept(_categories(privateMessages: _present));
      expect(controller.value.attentionEpoch, 1);
    },
  );

  test('request sequence stays monotonic through owner resets', () {
    final first = controller.nextRequestSequence();
    controller.setOwner(null);
    controller.setOwner(_owner);
    expect(controller.nextRequestSequence(), greaterThan(first));
  });

  test('repeated evidence and visibility retirement do not notify UI', () {
    accept(_mobile(_present));
    var notifications = 0;
    controller.addListener(() => notifications++);
    accept(_mobile(_present));
    controller.setMoreVisible(false);
    expect(notifications, 0);
    controller.setMoreVisible(true);
    expect(notifications, 1);
    controller.setMoreVisible(false);
    expect(notifications, 1);
  });

  test('disposal retires all late mutation without notifying', () {
    final retired = MessageAttentionController()..setOwner(_owner);
    retired.dispose();
    retired.setOwner(null);
    retired.accept(_mobile(_present), owner: _owner, sequence: 1);
    retired.setMoreVisible(true);
    retired.acknowledgeMore();
    expect(retired.value.hasAttention, isFalse);
  });
}
