/// 编辑器调用上下文：reply、newThread 或 postEdit。
///
/// 用于让通用层 service（如错误文案 presenter）按业务语境给出不同提示，
/// 同时保持 reply / posting 共用同一份实现。
enum ComposerKind { reply, newThread, postEdit }
