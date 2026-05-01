import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';

void main() {
  test('ComicShelfItem keeps constructor values', () {
    final item = ComicShelfItem(
      comicId: 'yamibo:100',
      title: '测试漫画',
      author: '作者A',
      coverImageUrl: 'https://img.test/1.jpg',
      categoryId: 'default',
      addedAt: DateTime(2026, 1, 1),
    );

    expect(item.comicId, 'yamibo:100');
    expect(item.title, '测试漫画');
    expect(item.author, '作者A');
    expect(item.coverImageUrl, 'https://img.test/1.jpg');
    expect(item.categoryId, 'default');
    expect(item.addedAt, DateTime(2026, 1, 1));
  });
}
