part of 'posting_composer_page_test.dart';

PostingComposerArgs _args({String fid = '33'}) {
  return PostingComposerArgs(target: PostingTarget(fid: fid));
}

NewThreadFormMetadata _metadata({
  bool typeRequired = false,
  String forumName = '日常版',
  List<ThreadType> types = const [
    ThreadType(id: '111', name: '日常'),
    ThreadType(id: '222', name: '汉化'),
  ],
}) {
  return NewThreadFormMetadata(
    fid: '33',
    forumName: forumName,
    formHash: 'fh',
    threadTypes: types,
    threadSorts: const <ThreadSort>[],
    typeRequired: typeRequired,
    sortRequired: false,
  );
}

/// 打开 PostingComposerPage 当作初始页：用于查看页面"自身"渲染的 widget 测试。
Widget _buildPage({
  PostingComposerArgs? args,
  ComposerDraftRepository? draftRepository,
  ComposerPreferencesRepository? preferencesRepository,
  PostingFormMetadataRepository? metadataRepository,
  NewThreadRepository? newThreadRepository,
  ComposerImagePicker? imagePicker,
  ComposerImageUploadCoordinator? imageUploadCoordinator,
  ThemeData? theme,
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
      postingFormMetadataRepositoryProvider.overrideWithValue(
        metadataRepository ?? _FakeMetadataRepository.success(_metadata()),
      ),
      newThreadRepositoryProvider.overrideWithValue(
        newThreadRepository ?? _FakeNewThreadRepository(),
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
  PostingFormMetadataRepository? metadataRepository,
  NewThreadRepository? newThreadRepository,
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
      postingFormMetadataRepositoryProvider.overrideWithValue(
        metadataRepository ?? _FakeMetadataRepository.success(_metadata()),
      ),
      newThreadRepositoryProvider.overrideWithValue(
        newThreadRepository ?? _FakeNewThreadRepository(),
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
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
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

class _FakeMetadataRepository implements PostingFormMetadataRepository {
  _FakeMetadataRepository._(this._queue, {this.holdUntil});

  factory _FakeMetadataRepository.success(NewThreadFormMetadata metadata) {
    return _FakeMetadataRepository._([
      ApiSuccess<NewThreadFormMetadata>(metadata),
    ]);
  }

  factory _FakeMetadataRepository.failure(ApiError error) {
    return _FakeMetadataRepository._([
      ApiFailure<NewThreadFormMetadata>(error),
    ]);
  }

  factory _FakeMetadataRepository.heldSuccess(
    NewThreadFormMetadata metadata,
    Future<void> holdUntil,
  ) {
    return _FakeMetadataRepository._([
      ApiSuccess<NewThreadFormMetadata>(metadata),
    ], holdUntil: holdUntil);
  }

  final List<ApiResult<NewThreadFormMetadata>> _queue;
  final Future<void>? holdUntil;
  ApiResult<NewThreadFormMetadata>? _last;
  int callCount = 0;

  void queueSuccess(NewThreadFormMetadata metadata) {
    _queue.add(ApiSuccess<NewThreadFormMetadata>(metadata));
  }

  @override
  Future<ApiResult<NewThreadFormMetadata>> getFormMetadata({
    required String fid,
  }) async {
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

class _FakeNewThreadRepository implements NewThreadRepository {
  _FakeNewThreadRepository({ApiResult<NewThreadSubmissionResult>? result})
    : _result =
          result ??
          const ApiSuccess<NewThreadSubmissionResult>(
            NewThreadSubmissionResult(
              tid: '900001',
              pid: '910001',
              message: '发布成功',
            ),
          );

  final ApiResult<NewThreadSubmissionResult> _result;
  final List<NewThreadDraftPayload> submittedPayloads =
      <NewThreadDraftPayload>[];

  @override
  Future<ApiResult<NewThreadSubmissionResult>> submit({
    required NewThreadDraftPayload payload,
  }) async {
    submittedPayloads.add(payload);
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
          errorMessage: event.errorMessage ?? '上传失败',
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
