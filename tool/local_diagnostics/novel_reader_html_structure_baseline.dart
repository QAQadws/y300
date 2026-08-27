import 'dart:convert';
import 'dart:io';

import 'package:y300/features/novel/presentation/models/novel_reader_html_structure_report.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_structure_analyzer.dart';

const _fixtureDirectory = 'docs/html/特殊格式';

const _fixtureFiles = <String, String>{
  '文字背景色': '文字背景色.html',
  '折叠目录': '折叠目录.html',
  '字颜色字号': '字颜色字号.html',
  '注音': '注音.html',
};

void main() {
  const analyzer = NovelReaderHtmlStructureAnalyzer();
  final reports = <NovelReaderHtmlStructureReport>[];
  for (final entry in _fixtureFiles.entries) {
    final path = '$_fixtureDirectory/${entry.value}';
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('Missing local diagnostic fixture: $path');
      exitCode = 2;
      return;
    }
    reports.add(
      analyzer.analyze(
        fixtureId: entry.key,
        rawHtml: utf8.decode(file.readAsBytesSync()),
      ),
    );
  }

  stdout.write(_renderMarkdown(reports));
}

String _renderMarkdown(List<NovelReaderHtmlStructureReport> reports) {
  final buffer = StringBuffer()
    ..writeln('# 小说阅读器 HTML 结构本地诊断')
    ..writeln()
    ..writeln(
      '> 本文件由 '
      '`dart run tool/local_diagnostics/'
      'novel_reader_html_structure_baseline.dart` 生成。',
    )
    ..writeln('> 仅输出结构计数，不输出正文、URL、Cookie、认证字段或本地路径。')
    ..writeln()
    ..writeln(
      '| 样本 | 源 UTF-8 字节 | 主楼 message | message UTF-8 字节 | '
      '普通文本节点 | 普通文本字符 | font | font-size | 前景色 | 背景色 | '
      '图片 | 折叠 | 展开折叠 | 表格 | 表格行 | 表格单元格 | ruby | rt | '
      'rp | script | message 敏感标记 |',
    )
    ..writeln(
      '| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | '
      '---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | '
      '---: | ---: | --- |',
    );
  for (final report in reports) {
    buffer.writeln(
      '| ${report.fixtureId} | ${report.sourceUtf8Bytes} | '
      '${report.messageFound ? report.messageSelector : "未找到"} | '
      '${report.messageUtf8Bytes} | ${report.ordinaryTextNodeCount} | '
      '${report.ordinaryTextRuneCount} | ${report.fontTagCount} | '
      '${report.fontSizeDeclarationCount} | '
      '${report.foregroundColorDeclarationCount} | '
      '${report.backgroundColorDeclarationCount} | ${report.imageCount} | '
      '${report.collapseBlockCount} | ${report.expandedCollapseBlockCount} | '
      '${report.tableCount} | ${report.tableRowCount} | '
      '${report.tableCellCount} | ${report.rubyCount} | '
      '${report.rubyAnnotationCount} | ${report.rubyFallbackCount} | '
      '${report.scriptCount} | '
      '${report.messageSensitiveMarkers.isEmpty ? "无" : report.messageSensitiveMarkers.join(", ")} |',
    );
  }
  return buffer.toString();
}
