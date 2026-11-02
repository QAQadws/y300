import 'package:flutter_test/flutter_test.dart';

import 'dart_dependency_directives.dart';

void main() {
  test('contextual identifiers cannot turn comparisons or calls into URI directives', () {
    const source = '''
import 'actual.dart';
void f() {
  for (final part in parts) {
    if (part == 'filled' || part == 'open') continue;
  }
  final export = 'not_an_export.dart';
  part('not_a_part.dart');
}
export 'public.dart' show Public;
''';
    expect(dartDependencyDirectiveUris(source), ['actual.dart', 'public.dart']);
    expect(dartExportShowLists(source), [
      ['Public'],
    ]);
  });

  test(
    'conditional branches and URI part-of relations remain real dependencies',
    () {
      const source = '''
import 'stub.dart' if (dart.library.io == 'true') 'io.dart';
export 'fallback.dart' if (dart.library.html) 'browser.dart' show A, B;
part 'child.dart';
part of 'parent.dart';
''';
      expect(dartDependencyDirectiveUris(source), [
        'stub.dart',
        'io.dart',
        'fallback.dart',
        'browser.dart',
        'child.dart',
        'parent.dart',
      ]);
      expect(dartExportShowLists(source), [
        ['A', 'B'],
      ]);
    },
  );

  test(
    'comments and strings do not hide a following forbidden real dependency',
    () {
      const source = '''
// import 'comment.dart';
/* export 'also_comment.dart'; /* nested part 'nested.dart'; */ */
const example = "part 'example.dart';";
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
''';
      expect(dartDependencyDirectiveUris(source), [
        'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart',
      ]);
    },
  );
}
