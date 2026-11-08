import 'package:flutter/material.dart';
import 'package:forum_content_renderer/experimental_continuous.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

// Standalone developer smoke target. Production routes keep their current
// renderer until resource/complex-format parity and paired measurements exist.
final continuousProbeController = ForumBodyContinuousController();

void main() {
  final body = const ForumBodyParser().parse(
    html: '''
<p style="color:#b00020">Continuous layout smoke sample</p>
<div>共享正文模型<br><br>连续排版与来源坐标。</div>
<blockquote>引用内的 <b>加粗</b>、<i>斜体</i>与颜色。</blockquote>
<ol start="8"><li>首项</li><li><a href="https://example.invalid/">链接项</a></li></ol>
<p style="text-indent:2em">作者缩进仅应用在首行。<br>换行延续正文。</p>
''',
    sourceId: 'continuous-probe',
    conversionIdentity: 'none',
  );
  runApp(
    MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ForumBodyContinuous(
              document: body,
              reader: ForumBodyReaderStyle(
                textStyle: const TextStyle(
                  fontSize: 18,
                  height: 1.5,
                  color: Colors.black,
                ),
                fontRevision: 'system-probe',
                linkColor: Colors.blue,
              ),
              controller: continuousProbeController,
            ),
          ),
        ),
      ),
    ),
  );
}
