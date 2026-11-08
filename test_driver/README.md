# Flutter MCP 调试入口

通过 Dart / Flutter MCP 的 `launch_app` 启动时，将 `target` 指定为
`test_driver/mcp_main.dart`，或在命令行运行：

```powershell
flutter run --debug -t test_driver/mcp_main.dart -d <device-id>
```

连接启动输出中的 DTD 后，可使用 `widget_inspector` 查看组件树，再通过
`flutter_driver_command` 操作实际控件、拖动和截图。`vm_service`、
`get_runtime_errors` 和 `hot_reload` 可用于检查状态与运行错误。

该入口在原有初始化前启用 Flutter Driver 服务扩展，仅用于开发验证。
正式构建继续使用 `lib/main.dart`，不启用 Driver；`flutter_driver` 仅为开发依赖。
