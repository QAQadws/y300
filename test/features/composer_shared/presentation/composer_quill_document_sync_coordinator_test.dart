import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/models/composer_insertion_models.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_bbcode_codec.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_document_sync_coordinator.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_embeds.dart';

const _codec = ComposerQuillBbCodeCodec();
const _attach = '[attach]42[/attach]';
const _collapse = '[collapse=0,标题]\n内部[/collapse]';

void main() {
  test(
    'literal attach promotion waits for a frame and preserves BBCode',
    () async {
      final fixture = _Fixture(document: _literal(_attach));
      final document = fixture.controller.document;
      await _flushMicrotasks();
      expect(document.toPlainText(), '$_attach\n');
      fixture.frames.removeAt(0)();
      expect(fixture.controller.document, same(document));
      expect(document.toDelta().first.data, isA<Map>());
      expect(fixture.controller.selection.baseOffset, 1);
      expect(fixture.sync.bbCode, _attach);
      expect(fixture.changes, isEmpty);
    },
  );

  test(
    'same-code replacement still normalizes without another writeback',
    () async {
      final fixture = _Fixture(document: _codec.decodeDocument(_attach));
      fixture.runFrames();
      fixture.controller.replaceText(
        0,
        1,
        _attach,
        const TextSelection.collapsed(offset: _attach.length),
      );
      expect(fixture.changes, isEmpty);
      expect(fixture.frames, hasLength(1));
      fixture.runFrames();
      await _flushMicrotasks();
      expect(fixture.controller.document.toDelta().first.data, isA<Map>());
      expect(fixture.controller.selection.baseOffset, 1);
      expect(fixture.changes, isEmpty);
    },
  );

  test(
    'local changes publish once and selection notifications only coalesce work',
    () {
      final fixture = _Fixture();
      fixture.controller.replaceText(
        0,
        0,
        '正文',
        const TextSelection.collapsed(offset: 2),
      );
      fixture.controller.updateSelection(
        const TextSelection.collapsed(offset: 1),
        ChangeSource.local,
      );
      expect(fixture.changes, ['正文']);
      expect(fixture.frames, hasLength(1));
      final document = fixture.controller.document;
      fixture.sync.applyExternalBbCode('正文', messageRevision: 99);
      expect(fixture.controller.document, same(document));
      expect(fixture.sync.documentGeneration, 0);
      expect(fixture.controller.selection.baseOffset, 1);
    },
  );

  test('collapse cleanup preserves document, selection and source', () async {
    final fixture = _Fixture(document: _codec.decodeDocument(_collapse));
    final document = fixture.controller.document;
    const selection = TextSelection(baseOffset: 0, extentOffset: 1);
    fixture.controller.updateSelection(selection, ChangeSource.local);
    fixture.controller.formatText(0, 1, Attribute.bold);
    fixture.controller.formatText(0, 1, Attribute.blockQuote);
    await _flushMicrotasks();
    expect(fixture.controller.document, same(document));
    expect(fixture.controller.selection, selection);
    expect(document.toDelta().first.attributes, isNull);
    expect(document.toDelta().toList()[1].attributes, isNull);
    expect(fixture.sync.bbCode, _collapse);
    expect(fixture.changes, isEmpty);
  });

  test('external raw source is not echoed as canonicalized BBCode', () async {
    final fixture = _Fixture();
    fixture.sync.applyExternalBbCode('[B]旧正文[/B]', messageRevision: 1);
    fixture.controller.updateSelection(
      const TextSelection.collapsed(offset: 1),
      ChangeSource.local,
    );
    fixture.runFrames();
    await _flushMicrotasks();
    expect(fixture.sync.bbCode, '[B]旧正文[/B]');
    expect(fixture.changes, isEmpty);
    fixture.controller.replaceText(
      1,
      0,
      '新',
      const TextSelection.collapsed(offset: 2),
    );
    expect(fixture.changes, ['[b]旧新正文[/b]']);
  });

  for (final matchesRevision in [true, false]) {
    test(
      'external insertion maps selection only for matching revision=$matchesRevision',
      () {
        final fixture = _Fixture();
        const source = '😀$_attach后';
        final sourceOffset = source.indexOf('后');
        fixture.sync.applyExternalBbCode(
          source,
          messageRevision: 2,
          mutation: ComposerTextMutation(
            previousSource: '😀后',
            nextSource: source,
            replacedSelection: const ComposerSelection(start: 2, end: 2),
            resultSelection: ComposerSelection(
              start: sourceOffset,
              end: sourceOffset,
            ),
            revision: matchesRevision ? 2 : 1,
          ),
        );
        expect(
          fixture.controller.selection.baseOffset,
          matchesRevision ? 3 : 4,
        );
        expect(fixture.changes, isEmpty);
      },
    );
  }

  test(
    'old frame callbacks neither mutate new documents nor release new work',
    () {
      final fixture = _Fixture(document: _literal(_attach));
      final first = fixture.controller.document;
      fixture.controller.document = _literal('[attach]7[/attach]');
      fixture.controller.document = first;
      expect(fixture.sync.documentGeneration, 2);
      expect(fixture.frames, hasLength(3));
      fixture.frames.removeAt(0)();
      expect(first.toPlainText(), '$_attach\n');
      fixture.controller.updateSelection(
        const TextSelection.collapsed(offset: _attach.length),
        ChangeSource.local,
      );
      expect(fixture.frames, hasLength(2));
      fixture.frames.removeAt(0)();
      expect(first.toPlainText(), '$_attach\n');
      fixture.frames.removeAt(0)();
      expect(first.toDelta().first.data, isA<Map>());
      expect(fixture.controller.selection.baseOffset, 1);
    },
  );

  test(
    'replacement retires queued cleanup without starving new cleanup',
    () async {
      final fixture = _Fixture(document: _codec.decodeDocument(_collapse));
      fixture.sync.applyExternalBbCode('新正文\n$_collapse', messageRevision: 1);
      final current = fixture.controller.document;
      fixture.controller.formatText(4, 1, Attribute.bold);
      fixture.controller.formatText(4, 1, Attribute.blockQuote);
      await _flushMicrotasks();
      final collapse = current.toDelta().toList().firstWhere(
        (operation) =>
            composerQuillCollapseEmbedPayload(operation.data) != null,
      );
      expect(collapse.attributes, isNull);
      expect(_codec.encodeDocument(current), '新正文\n$_collapse');
      expect(fixture.changes, isEmpty);
    },
  );

  test(
    'document replacement during promotion still normalizes its new generation',
    () {
      final fixture = _Fixture(document: _literal(_attach));
      var replaced = false;
      fixture.controller.addListener(() {
        if (!replaced &&
            fixture.controller.document.toDelta().first.data is Map) {
          replaced = true;
          fixture.controller.document = _literal('[attach]7[/attach]');
        }
      });
      fixture.runFrames();
      expect(fixture.controller.document.toPlainText(), '[attach]7[/attach]\n');
      expect(fixture.frames, hasLength(1));
      fixture.runFrames();
      expect(fixture.controller.document.toDelta().first.data, isA<Map>());
      expect(fixture.sync.bbCode, '[attach]7[/attach]');
    },
  );

  test('external apply reconciles a replacement made by another controller listener', () {
    final fixture = _Fixture();
    var replaced = false;
    fixture.controller.addListener(() {
      if (!replaced) {
        replaced = true;
        fixture.controller.document = _literal('调用方正文');
      }
    });
    fixture.sync.applyExternalBbCode('外部正文', messageRevision: 1);
    expect(fixture.sync.bbCode, '调用方正文');
    expect(fixture.sync.documentGeneration, 2);
    expect(fixture.changes, ['调用方正文']);
  });

  test(
    'reentrant external replacement keeps its source and retires old work',
    () {
      final controller = QuillController.basic();
      final frames = <void Function()>[];
      late final ComposerQuillDocumentSyncCoordinator sync;
      sync = ComposerQuillDocumentSyncCoordinator(
        controller: controller,
        scheduleAfterFrame: frames.add,
        onBbCodeChanged: (_) =>
            sync.applyExternalBbCode('外部正文', messageRevision: 1),
      );
      addTearDown(() {
        sync.close();
        controller.dispose();
      });
      controller.replaceText(
        0,
        0,
        _attach,
        const TextSelection.collapsed(offset: 0),
      );
      for (final frame in frames.toList()) {
        frame();
      }
      expect(sync.bbCode, '外部正文');
      expect(controller.document.toPlainText(), '外部正文\n');
    },
  );

  test(
    'close rejects queued work and detaches without disposing the controller',
    () async {
      final fixture = _Fixture(document: _literal(_attach));
      fixture.sync.close();
      fixture.sync.close();
      fixture.sync.applyExternalBbCode('忽略', messageRevision: 1);
      fixture.runFrames();
      await _flushMicrotasks();
      expect(fixture.controller.document.toPlainText(), '$_attach\n');
      fixture.controller.replaceText(
        0,
        0,
        '仍可编辑',
        const TextSelection.collapsed(offset: 0),
      );
      expect(fixture.changes, isEmpty);
      expect(fixture.frames, isEmpty);
    },
  );
}

Document _literal(String source) => Document.fromJson([
  {'insert': '$source\n'},
]);

Future<void> _flushMicrotasks() => Future<void>.delayed(Duration.zero);

final class _Fixture {
  _Fixture({Document? document}) {
    final initial = document ?? Document();
    controller = QuillController(
      document: initial,
      selection: TextSelection.collapsed(offset: initial.length - 1),
    );
    sync = ComposerQuillDocumentSyncCoordinator(
      controller: controller,
      scheduleAfterFrame: frames.add,
      onBbCodeChanged: changes.add,
    );
    addTearDown(() {
      sync.close();
      controller.dispose();
    });
  }
  late final QuillController controller;
  late final ComposerQuillDocumentSyncCoordinator sync;
  final frames = <void Function()>[];
  final changes = <String>[];

  void runFrames() {
    final pending = frames.toList();
    frames.clear();
    for (final frame in pending) {
      frame();
    }
  }
}
