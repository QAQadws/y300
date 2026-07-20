import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';

void main() {
  test('changes identity when any layout-affecting input changes', () {
    const base = NovelReaderPaginationKey(
      episodeId: 'episode',
      contentHash: 'content',
      viewportWidthPx: 320,
      viewportHeightPx: 600,
      typographySignature: 'font=18.5|line=1.6',
      themeSignature: 'sepia',
      imageDimensionRevision: 1,
      rendererRevision: 1,
    );

    expect(
      base ==
          const NovelReaderPaginationKey(
            episodeId: 'episode',
            contentHash: 'content',
            viewportWidthPx: 320,
            viewportHeightPx: 600,
            typographySignature: 'font=18.5|line=1.6',
            themeSignature: 'sepia',
            imageDimensionRevision: 1,
            rendererRevision: 1,
          ),
      isTrue,
    );
    expect(
      base ==
          const NovelReaderPaginationKey(
            episodeId: 'episode',
            contentHash: 'content',
            viewportWidthPx: 321,
            viewportHeightPx: 600,
            typographySignature: 'font=18.5|line=1.6',
            themeSignature: 'sepia',
            imageDimensionRevision: 1,
            rendererRevision: 1,
          ),
      isFalse,
    );
    expect(
      base.cacheIdentity,
      isNot(
        const NovelReaderPaginationKey(
          episodeId: 'episode',
          contentHash: 'content',
          viewportWidthPx: 320,
          viewportHeightPx: 600,
          typographySignature: 'font=18.5|line=1.6',
          themeSignature: 'dark',
          imageDimensionRevision: 1,
          rendererRevision: 1,
        ).cacheIdentity,
      ),
    );
  });

  test('normalizes unusable logical dimensions to zero', () {
    expect(NovelReaderPaginationKey.logicalPixels(-1), 0);
    expect(NovelReaderPaginationKey.logicalPixels(double.nan), 0);
    expect(NovelReaderPaginationKey.logicalPixels(320.4), 320);
  });
}
