import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/profile/domain/models/blog_draft_snapshot.dart';
import 'package:y300/features/profile/presentation/blog/blog_draft_coordinator.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_state.dart';
import '../test_support/blog_draft_fixture.dart';

void main() {
  late MemoryBlogDraftRepository repo;
  late BlogDraftCoordinator drafts;
  setUp(() async {
    repo = MemoryBlogDraftRepository();
    drafts = BlogDraftCoordinator(accountId: '101', repository: repo);
    await drafts.load();
  });
  tearDown(() => drafts.dispose());
  void edit(String value) => drafts.update(
    BlogEditorDraft(subject: value),
    changed: true,
    creatingCategory: false,
  );

  testWidgets(
    '700 ms debounce saves latest input and survives a new coordinator',
    (tester) async {
      drafts.dispose();
      drafts = BlogDraftCoordinator(accountId: '101', repository: repo);
      await drafts.load();
      edit('first');
      await tester.pump(const Duration(milliseconds: 600));
      expect(repo.values, isEmpty);
      edit('last');
      await tester.pump(const Duration(milliseconds: 700));
      expect(repo.values['101']!.subject, 'last');
      final reopened = BlogDraftCoordinator(accountId: '101', repository: repo);
      await reopened.load();
      expect(reopened.snapshot!.subject, 'last');
      reopened.dispose();
    },
  );
  test('flush captures immutable account content before expiry', () async {
    edit('old account');
    drafts.expire();
    await Future<void>.delayed(Duration.zero);
    expect(repo.values['101']!.subject, 'old account');
    drafts.update(
      const BlogEditorDraft(subject: 'late'),
      changed: true,
      creatingCategory: false,
    );
    expect(repo.values.containsKey('202'), isFalse);
  });
  test(
    'pending flag survives reload and requires durable acknowledgement',
    () async {
      edit('publish');
      expect(await drafts.setPending(true), isTrue);
      final reopened = BlogDraftCoordinator(accountId: '101', repository: repo);
      await reopened.load();
      expect(reopened.pending, isTrue);
      repo.failSave = true;
      expect(await reopened.setPending(false), isFalse);
      expect(reopened.pending, isTrue);
      expect(repo.values['101']!.pendingSubmission, isTrue);
      repo.failSave = false;
      expect(await reopened.setPending(false), isTrue);
      reopened.dispose();
    },
  );
  test('load failure cannot overwrite existing content', () async {
    edit('protected');
    await drafts.flush();
    repo.failLoad = true;
    final reopened = BlogDraftCoordinator(accountId: '101', repository: repo);
    expect(await reopened.load(), isFalse);
    reopened.update(
      const BlogEditorDraft(subject: 'empty'),
      changed: true,
      creatingCategory: false,
    );
    expect(await reopened.flush(), isFalse);
    expect(repo.values['101']!.subject, 'protected');
    reopened.dispose();
  });
  for (final complete in [false, true]) {
    test(
      'queued saves cannot resurrect after ${complete ? 'applied' : 'reset'}',
      () async {
        edit('old');
        final writing = drafts.flush();
        expect(await (complete ? drafts.complete() : drafts.reset()), isTrue);
        await writing;
        expect(repo.values, isEmpty);
        if (complete) {
          edit('late');
          await drafts.flush();
          expect(repo.values, isEmpty);
        }
      },
    );
  }
  test('save failure is retryable without dropping snapshot', () async {
    edit('kept');
    repo.failSave = true;
    expect(await drafts.flush(), isFalse);
    expect(drafts.snapshot!.subject, 'kept');
    repo.failSave = false;
    expect(await drafts.flush(), isTrue);
    expect(drafts.saveFailed, isFalse);
  });
  for (final complete in [false, true]) {
    test(
      'in-flight save finishes before ${complete ? 'applied cleanup' : 'reset deletion'}',
      () async {
        final gate = Completer<void>();
        repo.beforeSave = gate.future;
        edit('in flight');
        final writing = drafts.flush();
        await Future<void>.delayed(Duration.zero);
        final deleting = complete ? drafts.complete() : drafts.reset();
        gate.complete();
        await writing;
        expect(await deleting, isTrue);
        expect(repo.values, isEmpty);
      },
    );
  }
  test('load arriving after account expiry never restores content', () async {
    final gate = Completer<void>();
    edit('stored');
    await drafts.flush();
    repo.beforeLoad = gate.future;
    final reopened = BlogDraftCoordinator(accountId: '101', repository: repo);
    final loading = reopened.load();
    reopened.expire();
    gate.complete();
    expect(await loading, isFalse);
    expect(reopened.snapshot, isNull);
    expect(repo.values['101']!.subject, 'stored');
    reopened.dispose();
  });
  test('removed body image drops hint but leaves other HTML exact', () async {
    final image = BlogDraftImage(
      picId: '7',
      originalUri: Uri.parse('https://example.test/a.png'),
    );
    drafts.update(
      const BlogEditorDraft(
        bodyHtml: '<p><b>原文</b></p><img src="https://example.test/a.png">',
      ),
      changed: true,
      creatingCategory: false,
      images: [image],
    );
    expect(drafts.snapshot!.images, hasLength(1));
    drafts.update(
      const BlogEditorDraft(bodyHtml: '<table><tr><td>原文</td></tr></table>'),
      changed: true,
      creatingCategory: false,
    );
    expect(drafts.snapshot!.images, isEmpty);
    expect(drafts.snapshot!.bodyHtml, '<table><tr><td>原文</td></tr></table>');
  });
}
