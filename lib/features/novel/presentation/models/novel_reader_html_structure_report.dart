import 'dart:convert';

/// A privacy-safe structural snapshot of one HTML fixture.
///
/// The report deliberately contains counts and stable classification flags
/// only. It must never contain message text, URLs, cookies, request headers or
/// local file paths, so it can be attached to a performance review safely.
final class NovelReaderHtmlStructureReport {
  const NovelReaderHtmlStructureReport({
    required this.fixtureId,
    required this.sourceUtf8Bytes,
    required this.messageFound,
    required this.messageSelector,
    required this.messageUtf8Bytes,
    required this.messageTextRunes,
    required this.ordinaryTextNodeCount,
    required this.ordinaryTextRuneCount,
    required this.fontTagCount,
    required this.fontSizeDeclarationCount,
    required this.foregroundColorDeclarationCount,
    required this.backgroundColorDeclarationCount,
    required this.imageCount,
    required this.collapseBlockCount,
    required this.expandedCollapseBlockCount,
    required this.tableCount,
    required this.tableRowCount,
    required this.tableCellCount,
    required this.rubyCount,
    required this.rubyAnnotationCount,
    required this.rubyFallbackCount,
    required this.scriptCount,
    required this.messageSensitiveMarkers,
  });

  factory NovelReaderHtmlStructureReport.fromJson(Map<String, Object?> json) {
    return NovelReaderHtmlStructureReport(
      fixtureId: json['fixtureId']! as String,
      sourceUtf8Bytes: json['sourceUtf8Bytes']! as int,
      messageFound: json['messageFound']! as bool,
      messageSelector: json['messageSelector']! as String,
      messageUtf8Bytes: json['messageUtf8Bytes']! as int,
      messageTextRunes: json['messageTextRunes']! as int,
      ordinaryTextNodeCount: json['ordinaryTextNodeCount']! as int,
      ordinaryTextRuneCount: json['ordinaryTextRuneCount']! as int,
      fontTagCount: json['fontTagCount']! as int,
      fontSizeDeclarationCount: json['fontSizeDeclarationCount']! as int,
      foregroundColorDeclarationCount:
          json['foregroundColorDeclarationCount']! as int,
      backgroundColorDeclarationCount:
          json['backgroundColorDeclarationCount']! as int,
      imageCount: json['imageCount']! as int,
      collapseBlockCount: json['collapseBlockCount']! as int,
      expandedCollapseBlockCount: json['expandedCollapseBlockCount']! as int,
      tableCount: json['tableCount']! as int,
      tableRowCount: json['tableRowCount']! as int,
      tableCellCount: json['tableCellCount']! as int,
      rubyCount: json['rubyCount']! as int,
      rubyAnnotationCount: json['rubyAnnotationCount']! as int,
      rubyFallbackCount: json['rubyFallbackCount']! as int,
      scriptCount: json['scriptCount']! as int,
      messageSensitiveMarkers: _stringList(json['messageSensitiveMarkers']),
    );
  }

  final String fixtureId;
  final int sourceUtf8Bytes;
  final bool messageFound;
  final String messageSelector;
  final int messageUtf8Bytes;
  final int messageTextRunes;
  final int ordinaryTextNodeCount;
  final int ordinaryTextRuneCount;
  final int fontTagCount;
  final int fontSizeDeclarationCount;
  final int foregroundColorDeclarationCount;
  final int backgroundColorDeclarationCount;
  final int imageCount;
  final int collapseBlockCount;
  final int expandedCollapseBlockCount;
  final int tableCount;
  final int tableRowCount;
  final int tableCellCount;
  final int rubyCount;
  final int rubyAnnotationCount;
  final int rubyFallbackCount;
  final int scriptCount;
  final List<String> messageSensitiveMarkers;

  Map<String, Object> toJson() {
    return <String, Object>{
      'fixtureId': fixtureId,
      'sourceUtf8Bytes': sourceUtf8Bytes,
      'messageFound': messageFound,
      'messageSelector': messageSelector,
      'messageUtf8Bytes': messageUtf8Bytes,
      'messageTextRunes': messageTextRunes,
      'ordinaryTextNodeCount': ordinaryTextNodeCount,
      'ordinaryTextRuneCount': ordinaryTextRuneCount,
      'fontTagCount': fontTagCount,
      'fontSizeDeclarationCount': fontSizeDeclarationCount,
      'foregroundColorDeclarationCount': foregroundColorDeclarationCount,
      'backgroundColorDeclarationCount': backgroundColorDeclarationCount,
      'imageCount': imageCount,
      'collapseBlockCount': collapseBlockCount,
      'expandedCollapseBlockCount': expandedCollapseBlockCount,
      'tableCount': tableCount,
      'tableRowCount': tableRowCount,
      'tableCellCount': tableCellCount,
      'rubyCount': rubyCount,
      'rubyAnnotationCount': rubyAnnotationCount,
      'rubyFallbackCount': rubyFallbackCount,
      'scriptCount': scriptCount,
      'messageSensitiveMarkers': messageSensitiveMarkers,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  static List<String> _stringList(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    return List<String>.unmodifiable(value.whereType<String>());
  }
}
