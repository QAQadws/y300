part of 'posting_composer_page_test.dart';

PostingComposerArgs _args({String fid = '33'}) {
  return PostingComposerArgs(target: PostingTarget(fid: fid));
}

final class _TestThreadCreationToken implements ThreadCreationPreparationToken {
  const _TestThreadCreationToken();
}

final ThreadCreationCapabilities _threadCreationCapabilities =
    ThreadCreationCapabilities(
      values: DataCapabilitySet<ThreadCreationCapability>.supported(
        ThreadCreationCapability.values,
      ),
    );

ThreadCreationPreparation _metadata({
  bool typeRequired = false,
  String forumName = '日常版',
  List<ThreadCreationType> types = const [
    ThreadCreationType(id: '111', name: '日常'),
    ThreadCreationType(id: '222', name: '汉化'),
  ],
}) {
  return ThreadCreationPreparation(
    fid: '33',
    forumName: forumName,
    threadTypes: types,
    threadSorts: const <ThreadCreationSort>[],
    typeRequired: typeRequired,
    sortRequired: false,
    maxSubjectLength: 0,
    maxMessageLength: 0,
    token: const _TestThreadCreationToken(),
  );
}

/// 打开 PostingComposerPage 当作初始页：用于查看页面"自身"渲染的 widget 测试。
Widget _buildPage({
  PostingComposerArgs? args,
  ComposerDraftRepository? draftRepository,
  ComposerPreferencesRepository? preferencesRepository,
  ThreadCreationPreparationRepository? metadataRepository,
  ThreadCreationCommand? threadCreationCommand,
  ComposerImagePicker? imagePicker,
  ComposerImageUploadCoordinator? imageUploadCoordinator,
  ComposerDraftAttachmentVerificationService? draftVerificationService,
  ThemeData? theme,
  Locale locale = const Locale('zh'),
}) {
  return ProviderScope(
    overrides: [
      composerDraftRepositoryProvider.overrideWithValue(
        draftRepository ?? _MemoryDraftRepository(),
      ),
      composerPreferencesRepositoryProvider.overrideWithValue(
        preferencesRepository ?? _FakeComposerPreferencesRepository(),
      ),
      composerImagePickerProvider.overrideWithValue(
        imagePicker ?? _FakeImagePicker(),
      ),
      composerImageUploadCoordinatorProvider.overrideWithValue(
        imageUploadCoordinator ?? _FakeUploadCoordinator(),
      ),
      composerDraftAttachmentVerificationServiceProvider.overrideWithValue(
        draftVerificationService ??
            const _NoopPostingDraftAttachmentVerificationService(),
      ),
      threadCreationPreparationProvider.overrideWithValue(
        metadataRepository ?? _FakeMetadataRepository.success(_metadata()),
      ),
      threadCreationCommandProvider.overrideWithValue(
        threadCreationCommand ?? _FakeThreadCreationCommand(),
      ),
      forumBbCodeRendererProvider.overrideWithValue(
        const FlutterBbCodeForumRenderer(),
      ),
      stickerGroupsProvider.overrideWith((_) async => const []),
      stickerPickerPreferencesRepositoryProvider.overrideWithValue(
        _FakeStickerPickerPreferencesRepository(),
      ),
    ],
    child: LocalizedTestApp(
      locale: locale,
      theme: theme,
      home: PostingComposerPage(args: args ?? _args()),
    ),
  );
}

class _FakeComposerPreferencesRepository
    implements ComposerPreferencesRepository {
  _FakeComposerPreferencesRepository({ComposerPreferences? preferences})
    : preferences = preferences ?? ComposerPreferences.defaults();

  ComposerPreferences preferences;

  @override
  Future<ComposerPreferences> load() async => preferences;

  @override
  Future<void> save(ComposerPreferences preferences) async {
    this.preferences = preferences;
  }
}

/// 通过一个 launcher 按钮把页面 push 到外层 Navigator——这样 PopScope 行为
/// 与"返回上一页带 result"的真实场景一致，避免 MaterialApp 嵌套。
Widget _buildLauncher({
  PostingComposerArgs? args,
  ComposerDraftRepository? draftRepository,
  ThreadCreationPreparationRepository? metadataRepository,
  ThreadCreationCommand? threadCreationCommand,
  ComposerImagePicker? imagePicker,
  ComposerImageUploadCoordinator? imageUploadCoordinator,
  ThemeData? theme,
  ValueChanged<PostingComposerResult>? onResult,
}) {
  return ProviderScope(
    overrides: [
      composerDraftRepositoryProvider.overrideWithValue(
        draftRepository ?? _MemoryDraftRepository(),
      ),
      composerPreferencesRepositoryProvider.overrideWithValue(
        _FakeComposerPreferencesRepository(),
      ),
      composerImagePickerProvider.overrideWithValue(
        imagePicker ?? _FakeImagePicker(),
      ),
      composerImageUploadCoordinatorProvider.overrideWithValue(
        imageUploadCoordinator ?? _FakeUploadCoordinator(),
      ),
      composerDraftAttachmentVerificationServiceProvider.overrideWithValue(
        const _NoopPostingDraftAttachmentVerificationService(),
      ),
      threadCreationPreparationProvider.overrideWithValue(
        metadataRepository ?? _FakeMetadataRepository.success(_metadata()),
      ),
      threadCreationCommandProvider.overrideWithValue(
        threadCreationCommand ?? _FakeThreadCreationCommand(),
      ),
      forumBbCodeRendererProvider.overrideWithValue(
        const FlutterBbCodeForumRenderer(),
      ),
      stickerGroupsProvider.overrideWith((_) async => const []),
      stickerPickerPreferencesRepositoryProvider.overrideWithValue(
        _FakeStickerPickerPreferencesRepository(),
      ),
    ],
    child: LocalizedTestApp(
      theme: theme,
      home: _PostingComposerLauncher(
        args: args ?? _args(),
        onResult: onResult ?? ((_) {}),
      ),
    ),
  );
}

class _PostingComposerLauncher extends StatelessWidget {
  const _PostingComposerLauncher({required this.args, required this.onResult});

  final PostingComposerArgs args;
  final ValueChanged<PostingComposerResult> onResult;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          key: const Key('open-posting-composer-page'),
          onPressed: () async {
            final result = await Navigator.of(context)
                .push<PostingComposerResult>(
                  MaterialPageRoute<PostingComposerResult>(
                    builder: (_) => PostingComposerPage(args: args),
                  ),
                );
            if (result != null) {
              onResult(result);
            }
          },
          child: const Text('open'),
        ),
      ),
    );
  }
}

class _MemoryDraftRepository implements ComposerDraftRepository {
  final Map<String, ComposerDraftSnapshot> _drafts =
      <String, ComposerDraftSnapshot>{};

  @override
  Future<void> deleteDraft(ComposerDraftIdentity identity) async {
    _drafts.remove(identity.storageKey);
  }

  @override
  Future<List<ComposerDraftSnapshot>> listDraftsForThread({
    required String fid,
    required String tid,
  }) async {
    return _drafts.values
        .where(
          (draft) => draft.identity.fid == fid && draft.identity.tid == tid,
        )
        .toList(growable: false);
  }

  @override
  Future<ComposerDraftSnapshot?> loadDraft(
    ComposerDraftIdentity identity,
  ) async {
    return _drafts[identity.storageKey];
  }

  @override
  Future<ComposerDraftPruneResult> pruneDrafts({
    Duration maxAge = const Duration(days: 30),
    int maxCount = 100,
  }) async {
    return ComposerDraftPruneResult(removedCount: 0, keptCount: _drafts.length);
  }

  @override
  Future<void> saveDraft(ComposerDraftSnapshot draft) async {
    if (draft.isEmpty) {
      _drafts.remove(draft.identity.storageKey);
      return;
    }
    _drafts[draft.identity.storageKey] = draft;
  }
}

class _NoopPostingDraftAttachmentVerificationService
    implements ComposerDraftAttachmentVerificationService {
  const _NoopPostingDraftAttachmentVerificationService();

  @override
  Future<ComposerDraftAttachmentVerificationResult> verify(
    ComposerDraftSnapshot draft,
  ) async {
    return ComposerDraftAttachmentVerificationResult(
      draft: draft,
      verification: const ComposerDraftAttachmentVerification.notRequired(),
    );
  }
}

class _InvalidPostingDraftAttachmentVerificationService
    implements ComposerDraftAttachmentVerificationService {
  const _InvalidPostingDraftAttachmentVerificationService();

  @override
  Future<ComposerDraftAttachmentVerificationResult> verify(
    ComposerDraftSnapshot draft,
  ) async {
    return ComposerDraftAttachmentVerificationResult(
      draft: ComposerDraftSnapshot(
        identity: draft.identity,
        message: draft.message,
        useSignature: draft.useSignature,
        updatedAt: draft.updatedAt,
        subject: draft.subject,
        extras: draft.extras,
      ),
      verification: ComposerDraftAttachmentVerification.verified(
        imagesByAid: const {},
        checkedAids: const <String>{'123456'},
        invalidAidCount: 1,
      ),
    );
  }
}

class _FakeMetadataRepository implements ThreadCreationPreparationRepository {
  _FakeMetadataRepository._(this._queue, {this.holdUntil});

  factory _FakeMetadataRepository.success(ThreadCreationPreparation metadata) {
    return _FakeMetadataRepository._([
      DataReadSuccess<ThreadCreationPreparation, ThreadCreationCapabilities>(
        data: metadata,
        capabilities: _threadCreationCapabilities,
        metadata: const DataReadMetadata.network(),
      ),
    ]);
  }

  factory _FakeMetadataRepository.failure(
    DataReadFailure<ThreadCreationPreparation, ThreadCreationCapabilities>
    failure,
  ) {
    return _FakeMetadataRepository._([failure]);
  }

  factory _FakeMetadataRepository.heldSuccess(
    ThreadCreationPreparation metadata,
    Future<void> holdUntil,
  ) {
    return _FakeMetadataRepository._([
      DataReadSuccess<ThreadCreationPreparation, ThreadCreationCapabilities>(
        data: metadata,
        capabilities: _threadCreationCapabilities,
        metadata: const DataReadMetadata.network(),
      ),
    ], holdUntil: holdUntil);
  }

  final List<
    DataReadResult<ThreadCreationPreparation, ThreadCreationCapabilities>
  >
  _queue;
  final Future<void>? holdUntil;
  DataReadResult<ThreadCreationPreparation, ThreadCreationCapabilities>? _last;
  int callCount = 0;

  @override
  ThreadCreationCapabilities get capabilities => _threadCreationCapabilities;

  void queueSuccess(ThreadCreationPreparation metadata) {
    _queue.add(
      DataReadSuccess<ThreadCreationPreparation, ThreadCreationCapabilities>(
        data: metadata,
        capabilities: _threadCreationCapabilities,
        metadata: const DataReadMetadata.network(),
      ),
    );
  }

  @override
  Future<DataReadResult<ThreadCreationPreparation, ThreadCreationCapabilities>>
  load(ThreadCreationPreparationRequest request) async {
    callCount += 1;
    if (holdUntil != null && callCount == 1) {
      await holdUntil;
    }
    if (_queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      _last = next;
      return next;
    }
    return _last!;
  }
}

class _FakeThreadCreationCommand implements ThreadCreationCommand {
  _FakeThreadCreationCommand({DataCommandResult<ThreadCreationReceipt>? result})
    : _result =
          result ??
          const DataCommandApplied<ThreadCreationReceipt>(
            ThreadCreationReceipt(
              tid: '900001',
              pid: '910001',
              publicationState: ThreadPublicationState.published,
              readAccess: ThreadReadAccessEvidence(
                kind: ThreadReadAccessEvidenceKind.unrestricted,
                requested: 0,
                actual: 0,
              ),
            ),
          );

  final DataCommandResult<ThreadCreationReceipt> _result;
  final List<ThreadCreationSubmission> submissions =
      <ThreadCreationSubmission>[];

  @override
  ThreadCreationCapabilities get capabilities => _threadCreationCapabilities;

  @override
  Future<DataCommandResult<ThreadCreationReceipt>> execute(
    ThreadCreationSubmission submission,
  ) async {
    submissions.add(submission);
    return _result;
  }
}

class _FakeImagePicker implements ComposerImagePicker {
  _FakeImagePicker({this.images = const <ComposerPickedImage>[]});

  final List<ComposerPickedImage> images;
  int pickCallCount = 0;

  @override
  Future<List<ComposerPickedImage>> pickImagesInOrder() async {
    pickCallCount += 1;
    return images;
  }
}

class _FakeUploadCoordinator implements ComposerImageUploadCoordinator {
  _FakeUploadCoordinator({this.events = const <ComposerImageUploadEvent>[]});

  final List<ComposerImageUploadEvent> events;
  bool cancelled = false;

  @override
  void cancel() {
    cancelled = true;
  }

  @override
  Stream<ComposerImageUploadEvent> uploadInOrder({
    required String fid,
    required List<ComposerImageAttachment> attachments,
  }) async* {
    for (final event in events) {
      if (cancelled) return;
      if (event.type == ComposerImageUploadEventType.completed) {
        yield ComposerImageUploadEvent.completed(total: event.total);
        continue;
      }
      // 真实环境下 controller 在 pickImages 时给附件分配 localId，coordinator
      // 的事件会以那个 localId 回流。fake 里把传入的 attachments 替换进去，
      // 让 ComposerControllerBase._replaceAttachmentStatus 能匹配到。
      final localId = event.localId.isNotEmpty
          ? event.localId
          : attachments[(event.current - 1)
                    .clamp(0, attachments.length - 1)
                    .toInt()]
                .localId;
      yield switch (event.type) {
        ComposerImageUploadEventType.started =>
          ComposerImageUploadEvent.started(
            localId: localId,
            current: event.current,
            total: event.total,
          ),
        ComposerImageUploadEventType.progress =>
          ComposerImageUploadEvent.progress(
            localId: localId,
            current: event.current,
            total: event.total,
            progress: event.progress ?? 0,
          ),
        ComposerImageUploadEventType.uploaded =>
          ComposerImageUploadEvent.uploaded(
            localId: localId,
            current: event.current,
            total: event.total,
            uploadedImage: ComposerUploadedImage(
              localId: localId,
              aid: event.uploadedImage!.aid,
              uploadedAt: event.uploadedImage!.uploadedAt,
            ),
          ),
        ComposerImageUploadEventType.failed => ComposerImageUploadEvent.failed(
          localId: localId,
          current: event.current,
          total: event.total,
          failure:
              event.failure ??
              const ComposerImageUploadFailure(
                code: ComposerImageUploadFailureCode.unknown,
              ),
        ),
        ComposerImageUploadEventType.completed =>
          ComposerImageUploadEvent.completed(total: event.total),
      };
    }
  }
}

class _FakeStickerPickerPreferencesRepository
    implements StickerPickerPreferencesRepository {
  String? _last;

  @override
  Future<String?> loadLastGroupId() async => _last;

  @override
  Future<void> saveLastGroupId(String groupId) async {
    _last = groupId;
  }
}
