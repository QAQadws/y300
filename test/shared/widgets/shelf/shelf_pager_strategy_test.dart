import 'package:flutter_test/flutter_test.dart';
import 'package:y300/shared/widgets/shelf/shelf_pager_strategy.dart';

void main() {
  group('ShelfPagerStrategy', () {
    const strategy = ShelfPagerStrategy<_FakeCategory>(
      idOf: _idOf,
      labelOf: _labelOf,
    );

    test('buildTabs maps id and label in order', () {
      const categories = <_FakeCategory>[
        _FakeCategory(id: 'all', name: '全部'),
        _FakeCategory(id: 'fav', name: '收藏'),
      ];

      final tabs = strategy.buildTabs(categories);

      expect(tabs.length, 2);
      expect(tabs[0].id, 'all');
      expect(tabs[0].label, '全部');
      expect(tabs[1].id, 'fav');
      expect(tabs[1].label, '收藏');
    });

    test('resolveSelectedIndex returns matched index', () {
      const categories = <_FakeCategory>[
        _FakeCategory(id: 'all', name: '全部'),
        _FakeCategory(id: '49', name: '文学区'),
        _FakeCategory(id: '55', name: '轻小说'),
      ];
      final tabs = strategy.buildTabs(categories);

      final index = strategy.resolveSelectedIndex(
        tabs: tabs,
        selectedId: '55',
      );

      expect(index, 2);
    });

    test('resolveSelectedIndex falls back safely for unknown id', () {
      const categories = <_FakeCategory>[
        _FakeCategory(id: 'all', name: '全部'),
      ];
      final tabs = strategy.buildTabs(categories);

      final index = strategy.resolveSelectedIndex(
        tabs: tabs,
        selectedId: 'unknown',
        fallbackIndex: 10,
      );

      expect(index, 0);
    });
  });
}

class _FakeCategory {
  const _FakeCategory({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;
}

String _idOf(_FakeCategory item) => item.id;

String _labelOf(_FakeCategory item) => item.name;
