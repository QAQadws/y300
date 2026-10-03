import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/profile_friend_action_controller.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';

/// The caller re-reads its profile only after this sheet confirms applied.
Future<bool> showProfileFriendAction({
  required BuildContext context,
  required WidgetRef ref,
  required String targetUserId,
  required ForumUserProfileActionLink actionLink,
}) async {
  final owner = ref.read(verifiedProfileOwnerProvider);
  if (owner == null ||
      targetUserId == owner.uid ||
      !RegExp(r'^[1-9]\d*$').hasMatch(targetUserId) ||
      !{
        ForumUserProfileActionKind.addFriend,
        ForumUserProfileActionKind.removeFriend,
      }.contains(actionLink.kind)) {
    return false;
  }
  if (!_validFriendDestination(actionLink, targetUserId)) return false;
  final applied = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => ProfileFriendActionSheet(
      owner: owner,
      targetUserId: targetUserId,
      actionLink: actionLink,
    ),
  );
  return applied == true;
}

class ProfileFriendActionSheet extends ConsumerStatefulWidget {
  const ProfileFriendActionSheet({
    super.key,
    required this.owner,
    required this.targetUserId,
    required this.actionLink,
  });

  final VerifiedProfileOwner owner;
  final String targetUserId;
  final ForumUserProfileActionLink actionLink;

  @override
  ConsumerState<ProfileFriendActionSheet> createState() =>
      _ProfileFriendActionSheetState();
}

class _ProfileFriendActionSheetState
    extends ConsumerState<ProfileFriendActionSheet> {
  final _note = TextEditingController();
  late final ProfileFriendActionController _controller;
  ForumFriendPreparation? _lastPreparation;
  String? _groupId;

  @override
  void initState() {
    super.initState();
    final operations = ref.read(forumFriendOperationsProvider);
    _controller = ProfileFriendActionController(
      owner: widget.owner,
      targetUserId: widget.targetUserId,
      actionLink: widget.actionLink,
      currentOwner: () => ref.read(verifiedProfileOwnerProvider),
      prepare: operations.prepare,
      submit: operations.submit,
    );
    unawaited(_controller.prepare());
  }

  @override
  void dispose() {
    _controller.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final action = _controller.value.preparation?.action;
    final applied = await _controller.submit(
      note: _note.text,
      groupId: _groupId,
    );
    if (mounted &&
        applied &&
        action != null &&
        ref.read(verifiedProfileOwnerProvider) == widget.owner &&
        _controller.value.phase == ProfileFriendActionPhase.applied) {
      final l10n = AppLocalizations.of(context);
      final message = switch (action) {
        ForumFriendAction.request => l10n.profileFriendRequestSent,
        ForumFriendAction.approve => l10n.profileFriendApproved,
        ForumFriendAction.remove => l10n.profileFriendRemoved,
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _openForum() async {
    if (ref.read(verifiedProfileOwnerProvider) != widget.owner ||
        ModalRoute.of(context)?.isCurrent == false ||
        !_validFriendDestination(widget.actionLink, widget.targetUserId)) {
      return;
    }
    await Navigator.of(context).push<Object?>(
      ref.read(forumWebViewRouteFactoryProvider)(
        ForumWebViewLaunchConfig(
          initialUri: widget.actionLink.uri,
          popOnRootBack: true,
          expectedAccountId: widget.owner.uid,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(verifiedProfileOwnerProvider, (_, owner) {
      if (owner != widget.owner) _controller.expire();
    });
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          key: const Key('profile-friend-action-sheet'),
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: ValueListenableBuilder<ProfileFriendActionState>(
            valueListenable: _controller,
            builder: (context, state, _) {
              final preparation = state.preparation;
              if (preparation != null &&
                  !identical(preparation, _lastPreparation)) {
                _lastPreparation = preparation;
                _groupId =
                    preparation.groups.any((group) => group.id == _groupId)
                    ? _groupId
                    : preparation.groups.any(
                        (group) => group.id == preparation.selectedGroupId,
                      )
                    ? preparation.selectedGroupId
                    : preparation.groups.firstOrNull?.id;
              }
              final action =
                  preparation?.action ??
                  (widget.actionLink.kind ==
                          ForumUserProfileActionKind.removeFriend
                      ? ForumFriendAction.remove
                      : ForumFriendAction.request);
              final title = switch (action) {
                ForumFriendAction.request => l10n.profileFriendRequest,
                ForumFriendAction.approve => l10n.profileFriendApprove,
                ForumFriendAction.remove => l10n.profileFriendRemove,
              };
              final expired = state.phase == ProfileFriendActionPhase.expired;
              final ready = state.phase == ProfileFriendActionPhase.ready;
              final canOpenForum =
                  state.phase == ProfileFriendActionPhase.failed &&
                  state.preparation == null &&
                  state.failure is DataReadFailure &&
                  {
                    DataReadFailureKind.parse,
                    DataReadFailureKind.unsupported,
                  }.contains((state.failure as DataReadFailure).kind);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  if (expired)
                    Text(l10n.profileLoginRequired)
                  else if (state.phase == ProfileFriendActionPhase.preparing)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    Text(switch (action) {
                      ForumFriendAction.request =>
                        l10n.profileFriendRequestExplanation,
                      ForumFriendAction.approve =>
                        l10n.profileFriendApproveExplanation,
                      ForumFriendAction.remove =>
                        l10n.profileFriendRemoveExplanation,
                    }, style: TextStyle(color: scheme.onSurfaceVariant)),
                    if (preparation?.acceptsNote == true) ...[
                      const SizedBox(height: 20),
                      TextField(
                        key: const Key('profile-friend-note'),
                        controller: _note,
                        enabled: ready,
                        maxLength: preparation!.noteMaxLength,
                        minLines: 2,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: l10n.profileFriendNote,
                          hintText: l10n.profileFriendNoteHint,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ],
                    if (preparation?.groups.isNotEmpty == true) ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        key: ValueKey(preparation),
                        initialValue: _groupId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: l10n.profileFriendGroup,
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          for (final group in preparation!.groups)
                            DropdownMenuItem(
                              value: group.id,
                              child: Text(
                                group.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: ready
                            ? (groupId) => setState(() => _groupId = groupId)
                            : null,
                      ),
                    ],
                    if (state.failure != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          state.phase == ProfileFriendActionPhase.unknown
                              ? l10n.profileFriendOperationUnknown
                              : LocalizedErrorSummary.resolve(
                                  l10n,
                                  state.failure,
                                ),
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(l10n.commonClose),
                      ),
                      if (canOpenForum)
                        OutlinedButton(
                          key: const Key('profile-friend-open-forum'),
                          onPressed: _openForum,
                          child: Text(l10n.profileOpenForumPage),
                        ),
                      if (state.phase == ProfileFriendActionPhase.failed)
                        FilledButton(
                          key: const Key('profile-friend-retry'),
                          onPressed: _controller.prepare,
                          child: Text(l10n.commonRetry),
                        )
                      else if (!expired &&
                          state.phase != ProfileFriendActionPhase.unknown)
                        FilledButton(
                          key: const Key('profile-friend-submit'),
                          onPressed: ready ? _submit : null,
                          style: action == ForumFriendAction.remove
                              ? FilledButton.styleFrom(
                                  backgroundColor: scheme.error,
                                  foregroundColor: scheme.onError,
                                )
                              : null,
                          child: Text(
                            state.phase == ProfileFriendActionPhase.submitting
                                ? l10n.messageSending
                                : title,
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

bool _validFriendDestination(
  ForumUserProfileActionLink link,
  String targetUserId,
) {
  final site = Uri.parse(AppConfig.siteBaseUrl);
  final uri = link.uri;
  final parameters = uri.queryParametersAll;
  const allowed = {'mod', 'ac', 'op', 'uid', 'handlekey', 'mobile'};
  final removing = link.kind == ForumUserProfileActionKind.removeFriend;
  bool one(String key, String value) =>
      parameters[key]?.length == 1 && parameters[key]?.single == value;
  return uri.scheme == site.scheme &&
      uri.host == site.host &&
      uri.port == site.port &&
      uri.userInfo.isEmpty &&
      !uri.hasFragment &&
      uri.path == '/home.php' &&
      parameters.keys.every(allowed.contains) &&
      parameters.values.every((values) => values.length == 1) &&
      one('mod', 'spacecp') &&
      one('ac', 'friend') &&
      one('uid', targetUserId) &&
      (parameters['handlekey'] == null ||
          one(
            'handlekey',
            '${removing ? 'ignorefriendhk' : 'addfriendhk'}_$targetUserId',
          )) &&
      (parameters['mobile'] == null || one('mobile', '2')) &&
      one('op', removing ? 'ignore' : 'add');
}
