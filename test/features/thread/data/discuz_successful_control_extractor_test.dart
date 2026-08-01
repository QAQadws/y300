import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/thread/data/services/discuz_successful_control_extractor.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';

void main() {
  test('extracts browser successful controls in DOM order', () {
    final document = html_parser.parse('''
      <form id="postform">
        <input type="hidden" name="first" value="1">
        <fieldset disabled>
          <legend><input name="legend" value="kept"></legend>
          <input name="disabled-field" value="no">
          <textarea name="disabled-area">no</textarea>
        </fieldset>
        <input type="checkbox" name="checked" checked>
        <input type="checkbox" name="unchecked" value="no">
        <input type="radio" name="choice" value="a">
        <input type="radio" name="choice" value="b" checked>
        <select name="multi" multiple>
          <option value="1" selected>one</option>
          <option value="2">two</option>
          <option value="3" selected disabled>three</option>
        </select>
        <select name="default">
          <option value="first">first</option>
          <option value="second" selected>second</option>
        </select>
        <textarea name="message">原始 BBCode</textarea>
        <input name="attachnew[12]['description']" value="desc">
        <input type="file" name="Filedata">
        <button type="submit" name="submit">skip</button>
      </form>
    ''');

    final controls = const DiscuzSuccessfulControlExtractor().extract(
      document.querySelector('form')!,
    );

    expect(
      controls.fields.map((field) => '${field.name}=${field.value}'),
      <String>[
        'first=1',
        'legend=kept',
        'checked=on',
        'choice=b',
        'multi=1',
        'default=second',
        'message=原始 BBCode',
        "attachnew[12]['description']=desc",
      ],
    );
    expect(controls.namedControlNames, contains('disabled-field'));
    expect(controls.namedControlNames, contains('unchecked'));
    expect(controls.hasUnsupportedControlType, isFalse);
  });

  test(
    'uses the first enabled option when a single select has no selection',
    () {
      final document = html_parser.parse('''
      <form><select name="mode">
        <option disabled value="no">no</option>
        <option value="yes">yes</option>
      </select></form>
    ''');
      final controls = const DiscuzSuccessfulControlExtractor().extract(
        document.querySelector('form')!,
      );

      expect(controls.fields.single.value, 'yes');
      expect(
        controls.fields.single.controlKind,
        PostEditFormControlKind.select,
      );
    },
  );

  test('marks an enabled unknown input type without sending it', () {
    final document = html_parser.parse('''
      <form><input type="color" name="theme"></form>
    ''');
    final controls = const DiscuzSuccessfulControlExtractor().extract(
      document.querySelector('form')!,
    );

    expect(controls.fields, isEmpty);
    expect(controls.hasUnsupportedControlType, isTrue);
  });
}
