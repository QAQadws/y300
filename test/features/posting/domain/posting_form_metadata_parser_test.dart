import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/posting/domain/services/posting_form_metadata_parser.dart';

void main() {
  const parser = PostingFormMetadataParser();

  test('parses Map<typeid, name> threadtypes shape', () {
    final metadata = parser.parse(
      fid: '33',
      variables: <String, dynamic>{
        'formhash': 'fh-1',
        'forum': <String, dynamic>{'name': '随便聊聊'},
        'threadtypes': <String, dynamic>{
          'required': '1',
          'types': <String, dynamic>{
            '101': '杂谈',
            '102': '资源',
          },
        },
      },
    );

    expect(metadata.fid, '33');
    expect(metadata.forumName, '随便聊聊');
    expect(metadata.formHash, 'fh-1');
    expect(metadata.typeRequired, isTrue);
    expect(metadata.threadTypes, hasLength(2));
    final ids = metadata.threadTypes.map((t) => t.id).toSet();
    expect(ids, {'101', '102'});
  });

  test('parses List<{id|typeid, name|typename}> threadtypes shape', () {
    final metadata = parser.parse(
      fid: '33',
      variables: <String, dynamic>{
        'formhash': 'fh-2',
        'forum': <String, dynamic>{'name': '随便聊聊'},
        'threadtypes': <String, dynamic>{
          'required': 0,
          'types': <dynamic>[
            <String, dynamic>{'typeid': '201', 'typename': '问答'},
            <String, dynamic>{'id': '202', 'name': '心情'},
          ],
        },
      },
    );

    expect(metadata.typeRequired, isFalse);
    expect(metadata.threadTypes.map((t) => t.id), ['201', '202']);
    expect(metadata.threadTypes.map((t) => t.name), ['问答', '心情']);
  });

  test('returns empty thread types when threadtypes node is missing', () {
    final metadata = parser.parse(
      fid: '33',
      variables: <String, dynamic>{
        'formhash': 'fh-3',
        'forum': <String, dynamic>{'name': '随便聊聊'},
      },
    );
    expect(metadata.threadTypes, isEmpty);
    expect(metadata.threadSorts, isEmpty);
    expect(metadata.typeRequired, isFalse);
    expect(metadata.sortRequired, isFalse);
  });

  test('parses thread sorts independently of types', () {
    final metadata = parser.parse(
      fid: '33',
      variables: <String, dynamic>{
        'formhash': 'fh-4',
        'forum': <String, dynamic>{'name': '随便聊聊'},
        'threadsorts': <String, dynamic>{
          'required': '1',
          'types': <String, dynamic>{
            '301': '日常',
          },
        },
      },
    );
    expect(metadata.threadSorts, hasLength(1));
    expect(metadata.threadSorts.single.id, '301');
    expect(metadata.threadSorts.single.name, '日常');
    expect(metadata.sortRequired, isTrue);
  });
}
