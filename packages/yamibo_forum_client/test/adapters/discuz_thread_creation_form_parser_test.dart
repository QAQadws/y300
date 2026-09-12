import 'dart:io';

import 'package:html/parser.dart' as html;
import 'package:test/test.dart';
import 'package:yamibo_forum_client/src/adapters/discuz_read_access_parser.dart';
import 'package:yamibo_forum_client/src/adapters/discuz_thread_creation_form_parser.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

void main() {
  final ordinary = File(
    'test/fixtures/thread_creation/ordinary.html',
  ).readAsStringSync();
  final poll = File(
    'test/fixtures/thread_creation/poll.html',
  ).readAsStringSync();
  final uri = Uri.parse(
    'https://example.test/forum.php?mod=post&action=newthread&fid=30&mobile=2',
  );
  DiscuzThreadCreationForm parse(
    String source, {
    ThreadCreationKind kind = ThreadCreationKind.ordinary,
  }) => const DiscuzThreadCreationFormParser().parse(
    source,
    sourceUri: uri,
    requestedUri: uri,
    fid: '30',
    kind: kind,
  );

  test('template omissions remain unknown and duplicate groups merge', () {
    final form = parse(ordinary);
    expect(form.typeRequired, isNull);
    expect(form.maximumSubjectLength, isNull);
    expect(form.maximumMessageLength, isNull);
    expect(form.readAccess.currentValue, 0);
    expect(form.readAccess.options.map((e) => e.value), [0, 20, 40, 255]);
    expect(form.readAccess.options[1].groupNames, ['组 A', '组 B']);
  });

  test('poll limit comes from the emitted numeric assignment', () {
    final form = parse(poll, kind: ThreadCreationKind.poll);
    expect(form.pollConstraints!.maximumOptions, 32);
    expect(form.pollConstraints!.maximumOptionLength, isNull);
    expect(
      parse(
        poll.replaceFirst("parseInt('32')", "parseInt('7')"),
        kind: ThreadCreationKind.poll,
      ).pollConstraints!.maximumOptions,
      7,
    );
  });

  test('explicit form limits and required classification are preserved', () {
    final form = parse(
      ordinary
          .replaceFirst('name="typeid"', 'name="typeid" required')
          .replaceFirst('name="subject"', 'name="subject" maxlength="70"')
          .replaceFirst('name="message"', 'name="message" maxlength="9000"'),
    );
    expect(form.typeRequired, isTrue);
    expect(form.maximumSubjectLength, 70);
    expect(form.maximumMessageLength, 9000);
  });

  for (final change in <String, String>{
    'forum mismatch': ordinary.replaceFirst('fid=30', 'fid=31'),
    'missing hash': ordinary.replaceFirst('name="formhash"', 'name="missing"'),
    'missing timestamp': ordinary.replaceFirst(
      'name="posttime"',
      'name="missing"',
    ),
    'duplicate hash': ordinary.replaceFirst(
      '</form>',
      '<input name="formhash" value="other"></form>',
    ),
    'external action': ordinary.replaceFirst(
      'action="forum.php',
      'action="https://other.test/forum.php',
    ),
    'poll mismatch': poll,
    'captcha': ordinary.replaceFirst(
      '</form>',
      '<input name="seccodeverify"></form>',
    ),
    'sort form': ordinary.replaceFirst(
      '</form>',
      '<input name="sortid" value="4"></form>',
    ),
    'type info': ordinary.replaceFirst(
      '</form>',
      '<input name="typeoption[1]"></form>',
    ),
    'unsupported special': ordinary.replaceFirst(
      '</form>',
      '<input name="special" value="3"></form>',
    ),
    'external control':
        '$ordinary<input form="postform" name="readperm" value="0">',
  }.entries) {
    test(
      'refuses ${change.key}',
      () => expect(() => parse(change.value), throwsA(anything)),
    );
  }

  test('login and error pages return structured failure', () {
    expect(
      () => parse('<form id="loginform"></form>'),
      throwsA(
        isA<DiscuzCreationFormFailure>().having(
          (e) => e.kind,
          'kind',
          DataReadFailureKind.unauthorized,
        ),
      ),
    );
    expect(
      () => parse('<div class="jump_c">denied</div>'),
      throwsA(isA<DiscuzCreationFormFailure>()),
    );
  });

  ThreadReadAccess access(String control, {bool creating = false}) =>
      const DiscuzReadAccessParser().parse(
        html.parse('<form>$control</form>').querySelector('form')!,
        creating: creating,
      );

  test('same-valued selections normalize and 255 remains a threshold', () {
    final parsed = access(
      '<select name="readperm"><option value="20" selected>A</option><option value="20" selected>B</option><option value="255">C</option></select>',
    );
    expect(parsed.currentValue, 20);
    expect(parsed.options, hasLength(2));
    expect(parsed.options.first.groupNames, ['A', 'B']);
    expect(parsed.allows(255), isTrue);
  });

  test('conflicting selected thresholds and invalid numbers are rejected', () {
    for (final value in ['40', '-1', '256', 'abc']) {
      expect(
        () => access(
          '<select name="readperm"><option value="20" selected>A</option><option value="$value" selected>B</option></select>',
        ),
        throwsFormatException,
      );
    }
  });

  test(
    'empty explicit value is zero; missing selected is unknown only for edits',
    () {
      expect(
        access(
          '<select name="readperm"><option value="" selected>A</option></select>',
        ).currentValue,
        0,
      );
      const control =
          '<select name="readperm"><option value="">A</option></select>';
      expect(access(control).currentValue, isNull);
      expect(access(control, creating: true).currentValue, 0);
    },
  );

  test('attachment permissions never enable topic changes', () {
    final parsed = access('<input name="attachnew[5][readperm]" value="255">');
    expect(parsed.canModify, isFalse);
    expect(parsed.currentValue, isNull);
  });

  test('disabled controls and fieldsets preserve explicit evidence', () {
    for (final control in [
      '<select name="readperm" disabled><option value="20" selected>A</option></select>',
      '<fieldset disabled><select name="readperm"><option value="20" selected>A</option></select></fieldset>',
      '<input type="hidden" name="readperm" value="20">',
    ]) {
      expect(access(control).canModify, isFalse);
      expect(access(control).currentValue, 20);
    }
  });
}
