# 帖子编辑 Phase 0 fixtures

本目录保存帖子编辑入口与 WebView 兜底的脱敏契约样本。生产代码不会读取这些文件；它们只用于 parser、WebView 策略和后续编辑表单 anti-corruption layer 的回归测试。

## 来源与配对关系

| Fixture | 原始证据 | 目标身份 | 关系 |
| --- | --- | --- | --- |
| `mobile_thread_with_edit_links.html` | `docs/编辑/帖子页(有编辑按钮).html`，SHA-256 `40F531E85629E12BB611A502670C64E4CD7FCF0F0977DA35870E718289389045` | `fid=5`、`tid=557857`；保留两个已观察到的可编辑楼层 `pid=41587383`、`pid=41588620` | `pid=41587383` 与编辑表单严格配对；`pid=41588620` 只有入口证据 |
| `mobile_post_edit_form.html` | `docs/编辑/编辑页.html`，SHA-256 `8A43CCA8685523217B7B5923E559CE83516D3FC7CD43C0A19FD1328CBC2A064A` | `fid=5`、`tid=557857`、`pid=41587383`、`page=215` | 与上方同 pid 的楼层入口配对 |
| `desktop_thread_with_edit_links.html` | 根据移动版已确认 URL 契约制作的最小桌面 DOM | `tid=557857`，其余非法目标为合成边界 | 仅用于固定桌面 parser 边界，不声称是线上抓取 |

`manifest.json` 是上述关系的机器可读版本。实施方案中“两个现有样本 pid 不同”的旧判断不再成立：帖子页原始文件有两个编辑链接，其中 `pid=41587383` 与编辑页隐藏字段一致。

## 脱敏规则

- 删除 Cookie、`discuz_uid`、`cookiepre`、`REPORTURL`、外部脚本和运行时 bootstrap。
- 用户名、UID、头像、正文和附件路径替换为 fixture 值。
- `formhash` 与 `posttime` 替换为不可用于真实请求的测试值。
- 只保留验证协议所需的 DOM 结构、字段名、BBCode 标签、aid 和目标 ID。
- 原始目标 ID 只用于证明入口与表单的配对关系；fixture 不包含认证材料。

## 尚缺 P0 证据

以下资料当前没有本地抓包，不能用 Discuz 源码推断结果冒充真实响应：

1. 普通回复与首帖编辑成功的完整 multipart 字段顺序及响应 XML。
2. formhash 失效、登录失效和无权限响应。
3. 多张既有图片、普通文件附件以及 special/thread-sort/plugin 表单。

在这些证据补齐且后续 safe-submit 阶段完成前，生产入口必须继续只打开受管 WebView，不能开放原生提交。
