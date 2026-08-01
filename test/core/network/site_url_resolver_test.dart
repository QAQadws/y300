import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/site_url_resolver.dart';

void main() {
  const resolver = SiteUrlResolver();

  test('resolve keeps absolute url and decodes escaped ampersands', () {
    expect(
      resolver.resolve('https://bbs.yamibo.com/data/a.jpg?x=1&amp;y=2'),
      'https://bbs.yamibo.com/data/a.jpg?x=1&y=2',
    );
  });

  test('resolve handles relative root and protocol-relative urls', () {
    expect(
      resolver.resolve('data/attachment/a.jpg'),
      'https://bbs.yamibo.com/data/attachment/a.jpg',
    );
    expect(
      resolver.resolve('/data/attachment/b.jpg'),
      'https://bbs.yamibo.com/data/attachment/b.jpg',
    );
    expect(
      resolver.resolve('//bbs.yamibo.com/data/attachment/c.jpg'),
      'https://bbs.yamibo.com/data/attachment/c.jpg',
    );
  });

  test('resolve rewrites Discuz pseudo absolute attachment urls', () {
    expect(
      resolver.resolve(
        'http://data/attachment/sinaimg/tid503019/pid39465469/uid365616/page.jpg',
      ),
      'https://bbs.yamibo.com/data/attachment/sinaimg/tid503019/pid39465469/uid365616/page.jpg',
    );
    expect(
      resolver.resolve(
        'https://data/attachment/forum/201802/16/page.jpg?x=1&amp;y=2',
      ),
      'https://bbs.yamibo.com/data/attachment/forum/201802/16/page.jpg?x=1&y=2',
    );
  });
}
