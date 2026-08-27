# 本地私密样本诊断

本目录中的工具不会被普通 `flutter test` 自动发现，只用于开发者明确检查本机未提交的私密 HTML。正式回归必须使用 `test/fixtures` 中已经提交的最小合成样本。

```powershell
dart run tool/local_diagnostics/novel_reader_html_structure_baseline.dart
flutter test tool/local_diagnostics/forum_html_prototype_assets_diagnostic_test.dart
```

诊断缺少本地文件时会明确失败，不会把跳过结果当成回归通过。不要提交真实 HTML、诊断输出、Cookie、formhash 或其他认证数据。
