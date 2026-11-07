import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/presentation/services/thread_poll_option_presentation_store.dart';

void main() {
  test('option geometry is source-specific and retired by HTML, membership and owner changes', () {
    final store = ThreadPollOptionPresentationStore();
    final first = store.obtain('post', '1', '<p>First</p>');
    final otherOption = store.obtain('post', '2', '<p>First</p>');
    final otherPost = store.obtain('other', '1', '<p>First</p>');
    expect(first, isNot(same(otherOption)));
    expect(first, isNot(same(otherPost)));
    first.collapseExpansion['fold'] = true;
    first.recordLayout('body', 'layout', 400);
    expect(store.obtain('post', '1', '<p>First</p>'), same(first));
    final changed = store.obtain('post', '1', '<p>Edited</p>');
    expect(first.isActive, isFalse);
    expect(changed.heightFor('body', 'layout'), isNull);
    expect(changed.collapseExpansion, isEmpty);
    store.retainSources({
      'post': {'1': '<p>Edited</p>'},
    });
    expect(changed.isActive, isTrue);
    expect(otherOption.isActive, isFalse);
    expect(otherPost.isActive, isFalse);
    store.clear();
    expect(changed.isActive, isFalse);
    first.recordLayout('body', 'layout', 900);
    expect(first.heightFor('body', 'layout'), isNull);
    expect(store.obtain('post', '1', '<p>Edited</p>'), isNot(same(changed)));
    store.clear();
  });
}
