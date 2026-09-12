import 'dart:async';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

typedef BlogActionRead =
    DataReadResult<
      UserBlogActionPreparation,
      DataCapabilitySet<UserBlogAction>
    >;

typedef BlogEditorRead =
    DataReadResult<
      UserBlogEditorPreparation,
      DataCapabilitySet<UserBlogAction>
    >;

UserBlogTarget blogActionTarget(UserBlogAction action) => UserBlogTarget(
  actorUserId: '101',
  ownerUserId: '101',
  blogId: '11',
  action: action,
);

final class BlogOperationFixture implements UserBlogOperations {
  BlogOperationFixture({this.autoPrepare = false});
  final bool autoPrepare;
  UserBlogEditorPreparation Function(UserBlogTarget) editorForm =
      blogEditorPreparation;
  final editorPreparations =
      <
        ({
          UserBlogTarget target,
          ForumRequestCancellation? cancellation,
          Completer<BlogEditorRead> result,
        })
      >[];
  final editorSubmissions =
      <
        ({
          UserBlogEditorSubmission input,
          Completer<DataCommandResult<UserBlogReceipt>> result,
        })
      >[];
  final preparations =
      <
        ({
          UserBlogTarget target,
          ForumRequestCancellation? cancellation,
          Completer<BlogActionRead> result,
        })
      >[];
  final submissions =
      <
        ({
          UserBlogActionPreparation preparation,
          String actor,
          ForumRequestCancellation? cancellation,
          Completer<DataCommandResult<UserBlogReceipt>> result,
        })
      >[];

  @override
  Future<BlogActionRead> prepareAction(
    UserBlogTarget target, {
    ForumRequestCancellation? cancellation,
  }) {
    final result = Completer<BlogActionRead>();
    preparations.add((
      target: target,
      cancellation: cancellation,
      result: result,
    ));
    if (autoPrepare) prepared();
    return result.future;
  }

  void prepared({UserBlogTarget? target, bool supported = true, int? index}) {
    final request = preparations[index ?? preparations.length - 1];
    request.result.complete(
      DataReadSuccess(
        data: UserBlogActionPreparation(
          target: target ?? request.target,
          token: _Token(),
        ),
        capabilities: DataCapabilitySet.supported(
          supported ? [request.target.action] : [],
        ),
        metadata: const DataReadMetadata.network(),
      ),
    );
  }

  @override
  Future<DataCommandResult<UserBlogReceipt>> executeAction(
    UserBlogActionPreparation preparation, {
    required String actorUserId,
    ForumRequestCancellation? cancellation,
  }) {
    final result = Completer<DataCommandResult<UserBlogReceipt>>();
    submissions.add((
      preparation: preparation,
      actor: actorUserId,
      cancellation: cancellation,
      result: result,
    ));
    return result.future;
  }

  void applied({UserBlogTarget? target, String? blogId}) {
    final request = submissions.last;
    request.result.complete(
      DataCommandApplied(
        UserBlogReceipt(
          target: target ?? request.preparation.target,
          blogId: blogId ?? request.preparation.target.blogId!,
        ),
      ),
    );
  }

  @override
  Future<
    DataReadResult<UserBlogEditorPreparation, DataCapabilitySet<UserBlogAction>>
  >
  prepareEditor(
    UserBlogTarget target, {
    ForumRequestCancellation? cancellation,
  }) {
    final result = Completer<BlogEditorRead>();
    editorPreparations.add((
      target: target,
      cancellation: cancellation,
      result: result,
    ));
    if (autoPrepare) preparedEditor();
    return result.future;
  }

  void preparedEditor({
    UserBlogEditorPreparation? form,
    bool supported = true,
  }) {
    final request = editorPreparations.last;
    request.result.complete(
      DataReadSuccess(
        data: form ?? editorForm(request.target),
        capabilities: DataCapabilitySet.supported(
          supported ? [request.target.action] : [],
        ),
        metadata: const DataReadMetadata.network(),
      ),
    );
  }

  @override
  Future<DataCommandResult<UserBlogReceipt>> save(
    UserBlogEditorSubmission submission,
  ) {
    final result = Completer<DataCommandResult<UserBlogReceipt>>();
    editorSubmissions.add((input: submission, result: result));
    return result.future;
  }

  void saved({UserBlogTarget? target, String? blogId}) {
    final request = editorSubmissions.last;
    request.result.complete(
      DataCommandApplied(
        UserBlogReceipt(
          target: target ?? request.input.preparation.target,
          blogId: blogId ?? request.input.preparation.target.blogId ?? '12',
        ),
      ),
    );
  }
}

UserBlogEditorPreparation blogEditorPreparation(
  UserBlogTarget target, {
  String? subject,
  String? bodyHtml,
  String tags = 'original tag',
  List<UserBlogCategory> siteCategories = const [
    UserBlogCategory(id: '0', name: 'None'),
    UserBlogCategory(id: '8', name: 'Stories'),
  ],
  List<UserBlogCategory> personalCategories = const [
    UserBlogCategory(id: '0', name: 'None'),
    UserBlogCategory(id: '9', name: 'Travel'),
  ],
  bool siteCategoryRequired = false,
  bool canCreateCategory = true,
  bool canPublishFeed = true,
  UserBlogVisibility visibility = UserBlogVisibility.public,
  bool commentsEnabled = true,
}) => UserBlogEditorPreparation(
  target: target,
  token: _Token(),
  subject:
      subject ??
      (target.action == UserBlogAction.create ? '' : 'Original title'),
  bodyHtml:
      bodyHtml ??
      (target.action == UserBlogAction.create
          ? ''
          : '<p class="original">原文 &amp; text</p>'),
  tags: tags,
  siteCategories: siteCategories,
  personalCategories: personalCategories,
  siteCategoryId: '0',
  personalCategoryId: '0',
  siteCategoryRequired: siteCategoryRequired,
  canCreateCategory: canCreateCategory,
  canPublishFeed: canPublishFeed,
  publishFeed: false,
  visibility: visibility,
  commentsEnabled: commentsEnabled,
);

final class _Token implements UserBlogOperationToken {}

const blogActionReadFailure =
    DataReadFailure<
      UserBlogActionPreparation,
      DataCapabilitySet<UserBlogAction>
    >(
      kind: DataReadFailureKind.network,
      diagnosticMessage: 'fixture prepare failed',
    );
const blogActionWriteFailure = DataCommandFailure(
  kind: DataCommandFailureKind.network,
  retryPolicy: DataCommandRetryPolicy.explicitOnly,
  diagnosticMessage: 'fixture write failed',
);
