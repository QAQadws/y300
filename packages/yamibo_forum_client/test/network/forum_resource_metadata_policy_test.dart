import 'dart:convert';

import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart'
    show ForumResourceMetadataPolicy;

void main() {
  final dynamicUri = Uri.parse('https://images.example.invalid/dynamic');

  group('existing image signatures', () {
    final examples = <({String name, List<int> bytes, String extension})>[
      (name: 'JPEG', bytes: <int>[0xff, 0xd8, 0xff], extension: '.jpg'),
      (
        name: 'PNG',
        bytes: <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
        extension: '.png',
      ),
      (name: 'GIF', bytes: ascii.encode('GIF8'), extension: '.gif'),
      (name: 'BMP', bytes: ascii.encode('BM'), extension: '.bmp'),
      (name: 'ICO', bytes: <int>[0x00, 0x00, 0x01, 0x00], extension: '.ico'),
      (
        name: 'WebP',
        bytes: <int>[
          ...ascii.encode('RIFF'),
          0,
          0,
          0,
          0,
          ...ascii.encode('WEBP'),
        ],
        extension: '.webp',
      ),
      for (final brand in <String>['avif', 'avis'])
        (name: 'AVIF $brand', bytes: _isoBmffPrefix(brand), extension: '.avif'),
      for (final brand in <String>[
        'heic',
        'heix',
        'hevc',
        'hevx',
        'mif1',
        'msf1',
      ])
        (name: 'HEIC $brand', bytes: _isoBmffPrefix(brand), extension: '.heic'),
      (name: 'SVG', bytes: utf8.encode('<svg/>'), extension: '.svg'),
      (
        name: 'SVG with whitespace and case variation',
        bytes: utf8.encode(' \n\t<SVG/>'),
        extension: '.svg',
      ),
      (
        name: 'XML SVG',
        bytes: utf8.encode('<?xml version="1.0"?><svg/>'),
        extension: '.svg',
      ),
    ];

    for (final example in examples) {
      test('recognizes ${example.name} with a misleading MIME type', () {
        expect(
          ForumResourceMetadataPolicy.isSupportedImage(
            'text/html',
            example.bytes,
          ),
          isTrue,
        );
        expect(
          ForumResourceMetadataPolicy.imageFileExtension(
            'text/html',
            dynamicUri,
            signature: example.bytes,
          ),
          example.extension,
        );
      });
    }

    final invalid = <String, List<int>>{
      'empty body': <int>[],
      'truncated JPEG': <int>[0xff, 0xd8],
      'truncated PNG': <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a],
      'truncated GIF': ascii.encode('GIF'),
      'truncated BMP': ascii.encode('B'),
      'truncated ICO': <int>[0, 0, 1],
      'truncated WebP': <int>[
        ...ascii.encode('RIFF'),
        0,
        0,
        0,
        0,
        ...ascii.encode('WEB'),
      ],
      'truncated AVIF': _isoBmffPrefix('avif').take(11).toList(),
      'truncated HEIC': _isoBmffPrefix('heic').take(11).toList(),
      'truncated SVG opening': utf8.encode('<sv'),
      'XML without SVG': utf8.encode('<?xml version="1.0"?><document/>'),
      'RIFF audio': <int>[
        ...ascii.encode('RIFF'),
        0,
        0,
        0,
        0,
        ...ascii.encode('WAVE'),
      ],
      'other ISO BMFF brand': _isoBmffPrefix('mp42'),
      'HTML body': utf8.encode('<html><img src="image.jpg"></html>'),
    };
    for (final example in invalid.entries) {
      test('does not classify ${example.key} as an image signature', () {
        expect(
          ForumResourceMetadataPolicy.isSupportedImage(null, example.value),
          isFalse,
        );
        expect(
          ForumResourceMetadataPolicy.imageFileExtension(
            null,
            dynamicUri,
            signature: example.value,
          ),
          isEmpty,
        );
      });
    }

    test('SVG inspection stays within the existing 1024-byte limit', () {
      final bytes = <int>[
        ...List<int>.filled(1024, 32),
        ...utf8.encode('<svg/>'),
      ];
      expect(
        ForumResourceMetadataPolicy.isSupportedImage(null, bytes),
        isFalse,
      );
    });
  });

  group('MIME and extension metadata', () {
    const mimeExtensions = <String, String>{
      'image/jpeg': '.jpg',
      'image/png': '.png',
      'image/gif': '.gif',
      'image/webp': '.webp',
      'image/avif': '.avif',
      'image/svg+xml': '.svg',
      'image/bmp': '.bmp',
      'image/x-icon': '.ico',
      'image/vnd.microsoft.icon': '.ico',
    };
    for (final entry in mimeExtensions.entries) {
      test('normalizes ${entry.key} with whitespace, case and parameters', () {
        final contentType = ' ${entry.key.toUpperCase()}; charset=binary ';
        expect(
          ForumResourceMetadataPolicy.hasDeclaredImageContentType(contentType),
          isTrue,
        );
        expect(
          ForumResourceMetadataPolicy.isSupportedImage(contentType, <int>[]),
          isTrue,
        );
        expect(
          ForumResourceMetadataPolicy.imageFileExtension(
            contentType,
            dynamicUri,
          ),
          entry.value,
        );
      });
    }

    test('retains the declared image fast path for an unknown subtype', () {
      const contentType = 'image/x-custom';
      expect(
        ForumResourceMetadataPolicy.hasDeclaredImageContentType(contentType),
        isTrue,
      );
      expect(
        ForumResourceMetadataPolicy.isSupportedImage(contentType, <int>[]),
        isTrue,
      );
      expect(
        ForumResourceMetadataPolicy.imageFileExtension(contentType, dynamicUri),
        isEmpty,
      );
    });

    test('chooses signature before MIME, and recognized MIME before URI', () {
      final uri = Uri.parse('https://images.example.invalid/image.gif');
      expect(
        ForumResourceMetadataPolicy.imageFileExtension(
          'image/png',
          uri,
          signature: <int>[0xff, 0xd8, 0xff],
        ),
        '.jpg',
      );
      expect(
        ForumResourceMetadataPolicy.imageFileExtension(
          'image/png',
          uri,
          signature: <int>[],
        ),
        '.png',
      );
      expect(ForumResourceMetadataPolicy.imageFileExtension(null, uri), '.gif');
    });

    test('URI naming metadata cannot prove image content', () {
      final uri = Uri.parse('https://images.example.invalid/image.jpg');
      final html = utf8.encode('<html>unavailable</html>');
      expect(
        ForumResourceMetadataPolicy.imageFileExtension(
          null,
          uri,
          signature: html,
        ),
        '.jpg',
      );
      expect(ForumResourceMetadataPolicy.isSupportedImage(null, html), isFalse);
      for (final contentType in <String>[
        '',
        'text/html',
        'image',
        'x-image/png',
      ]) {
        expect(
          ForumResourceMetadataPolicy.hasDeclaredImageContentType(contentType),
          isFalse,
          reason: contentType,
        );
      }
    });

    const uriExtensions = <String, String>{
      '/image.JPEG': '.jpeg',
      '/image.A1': '.a1',
      '/.png': '.png',
      '/image.png?name=other.gif#photo': '.png',
      '/folder/': '',
      '/dynamic': '',
      '/image.': '',
      '/image.abcdef': '',
      '/image.p-ng': '',
      '/image.图片': '',
    };
    for (final entry in uriExtensions.entries) {
      test('URI fallback for ${entry.key}', () {
        expect(
          ForumResourceMetadataPolicy.imageFileExtension(
            'application/octet-stream',
            Uri.parse('https://images.example.invalid${entry.key}'),
          ),
          entry.value,
        );
      });
    }
  });

  group('current cache-lifetime behavior', () {
    // These combinations characterize the existing response-order policy. A
    // directive-precedence correction must be reviewed separately from deduping.
    const examples = <({String name, String? value, Duration lifetime})>[
      (name: 'absent', value: null, lifetime: Duration(days: 7)),
      (name: 'empty', value: '', lifetime: Duration(days: 7)),
      (name: 'unrecognized', value: 'private', lifetime: Duration(days: 7)),
      (name: 'max-age', value: 'max-age=90', lifetime: Duration(seconds: 90)),
      (name: 'zero max-age', value: 'max-age=0', lifetime: Duration.zero),
      (
        name: 'case and whitespace',
        value: ' MAX-AGE=90 ',
        lifetime: Duration(seconds: 90),
      ),
      (name: 'negative age', value: 'max-age=-1', lifetime: Duration(days: 7)),
      (
        name: 'invalid age',
        value: 'max-age=invalid',
        lifetime: Duration(days: 7),
      ),
      (name: 'quoted age', value: 'max-age="90"', lifetime: Duration(days: 7)),
      (name: 'no-cache', value: 'no-cache', lifetime: Duration.zero),
      (name: 'no-store', value: 'no-store', lifetime: Duration.zero),
      (
        name: 'no-store then age',
        value: 'no-store, max-age=90',
        lifetime: Duration(seconds: 90),
      ),
      (
        name: 'age then no-store',
        value: 'max-age=90, no-store',
        lifetime: Duration.zero,
      ),
      (
        name: 'no-cache then age',
        value: 'no-cache, max-age=90',
        lifetime: Duration(seconds: 90),
      ),
      (
        name: 'age then no-cache',
        value: 'max-age=90, no-cache',
        lifetime: Duration.zero,
      ),
      (
        name: 'duplicate ages',
        value: 'max-age=90, max-age=12',
        lifetime: Duration(seconds: 12),
      ),
      (
        name: 'invalid later age',
        value: 'max-age=90, max-age=invalid',
        lifetime: Duration(seconds: 90),
      ),
      (
        name: 'negative later age',
        value: 'max-age=90, max-age=-1',
        lifetime: Duration(seconds: 90),
      ),
      (
        name: 'invalid age after no-store',
        value: 'no-store, max-age=invalid',
        lifetime: Duration.zero,
      ),
      (
        name: 'negative age after no-store',
        value: 'no-store, max-age=-1',
        lifetime: Duration.zero,
      ),
      (
        name: 'later age restores lifetime',
        value: 'max-age=90, no-cache, max-age=12',
        lifetime: Duration(seconds: 12),
      ),
    ];
    for (final example in examples) {
      test('cache lifetime retains response order: ${example.name}', () {
        final headers = <String, List<String>>{
          if (example.value != null) 'Cache-Control': <String>[example.value!],
        };
        expect(
          ForumResourceMetadataPolicy.cacheLifetime(headers),
          example.lifetime,
        );
      });
    }

    const headerExamples =
        <({String name, Map<String, List<String>> headers, Duration lifetime})>[
          (
            name: 'case-insensitive header',
            headers: <String, List<String>>{
              'CACHE-CONTROL': <String>['max-age=12'],
            },
            lifetime: Duration(seconds: 12),
          ),
          (
            name: 'only the first value is read',
            headers: <String, List<String>>{
              'Cache-Control': <String>['max-age=90', 'no-store'],
            },
            lifetime: Duration(seconds: 90),
          ),
          (
            name: 'an empty first value is not merged with later values',
            headers: <String, List<String>>{
              'Cache-Control': <String>['', 'max-age=90'],
            },
            lifetime: Duration(days: 7),
          ),
          (
            name: 'empty header entries are skipped',
            headers: <String, List<String>>{
              'CACHE-CONTROL': <String>[],
              'Cache-Control': <String>['max-age=12'],
            },
            lifetime: Duration(seconds: 12),
          ),
          (
            name: 'later differently-cased entries are not merged',
            headers: <String, List<String>>{
              'CACHE-CONTROL': <String>['max-age=90'],
              'Cache-Control': <String>['no-store'],
            },
            lifetime: Duration(seconds: 90),
          ),
        ];
    for (final example in headerExamples) {
      test('cache header selection: ${example.name}', () {
        expect(
          ForumResourceMetadataPolicy.cacheLifetime(example.headers),
          example.lifetime,
        );
      });
    }
  });
}

List<int> _isoBmffPrefix(String brand) => <int>[
  0,
  0,
  0,
  20,
  ...ascii.encode('ftyp$brand'),
];
