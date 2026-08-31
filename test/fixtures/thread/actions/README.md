# 帖子动作表单测试样本

本目录只保存手工构造的最小 Discuz 评分表单，用于应用侧评分投影回归测试。它不是线上页面的脱敏副本，也不依赖 `docs/` 中的本地抓取文件。

固定测试身份：

- `tid=10001`
- `pid=20001`
- `uid=30001`
- `formhash=fixture-formhash`
- `username=fixture-user`

样本只保留投影所需的 CDATA、form action、hidden input、评分范围和合成理由。禁止加入 Cookie、真实 formhash、账号、正文、附件 key、响应脚本或其他无关页面内容。
