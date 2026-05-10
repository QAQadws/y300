目前解析的是fid为30的漫画版块的帖子的massage
对于一个帖子，解析连续的从一楼开始的楼主的信息
比如有的漫画结构上一楼楼主发布漫画信息，二楼楼主又发布漫画，三楼楼主又发布部分信息
不过大多数漫画都在一楼实现了全部的漫画发布
目前我只实现了对于message中的图片和部分链接的解析，这次我想实现更加完整和工程化的重构，并且易于添加规则
目前我们主要从message中解析图片和跳转链接，比如跳转到上一话和跳转到目录
我给你一一介绍
方式一：
在最新话的massage中又之前话的全部跳转链接
链接可能有两种	动态参数链接和伪静态链接，形式可能如下
<a href=";tid=537155&amp;highlight=%E5%B9%B3%E8%89%AF%E6%B7%B1">04</a>
<a href="https:///thread-544245-1-1.html">09</a>
因为我们是api实现，所以主要需要在这些链接中解析帖子编号即可
对于超链接文字可能有如下
01，第一话，第1话，特典，第一卷特典
不过我只是举了几个例子而已实际情况可能很复杂，有时候连续的多个链接也是一个很关键的信息，所以我希望能解构出来使得能方便添加规则
方式二：
在最新话的massage中只有上一话的跳转链接，然后一直递归下去，才能获取全部的漫画
所以有时候也要结合subject中的信息（比如当前是第几话）来判断是否有上一话，和message中是否有上一话的链接
方式三：
有时候message中有的超链接文本带"目录"字样，这就表示这个链接跳转到一个这个漫画的目录网站，不过这个目录没有api形式，所以我们只能对其html进行解析，非常的麻烦
当有前面的跳转链接时，不考虑解析目录
但有时候又是必要的
我给你一些信息辅助你解析目录的html
1.
目录链接形式如https://bbs.yamibo.com/misc.php?mod=tag&id=21137或者https://bbs.yamibo.com/misc.php?mod=tag&id=20452&type=thread&page=1，所以可能有多页
这个跳转链接也没有移动版网页，所以不可以加mobile=2参数
html内容非常多，所以给你截取了部分而已
```html
<a href="space-uid-244692.html" c="1">鹿角小黑猫</a>
</cite>
<em><span>2024-11-27</span></em>
</td>
<td class="num">
<a href="thread-552062-1-1.html" class="xi2">19</a>
<em>4199</em>
</td>
<td class="by">
<cite><a href="space-username-Shigatsu.html" c="1">Shigatsu</a></cite>
<em><a href="forum.php?mod=redirect&tid=552062&goto=lastpost#lastpost">2026-5-1 17:45</a></em>
</td>
</tr>
<tr>
<td class="icn">
<a href="thread-553686-1-1.html" title="新窗口打开" target="_blank">
<i class="fico-thread fic6 fc-n"></i>
</a>
</td>
<th>
<a href="thread-553686-1-1.html" target="_blank" >【猫咪阳台】[樫風] 谱为君嗥-第1卷附录&amp;蜜瓜特典</a>
<i class="fico-image fic4 fc-p fnmr vm" title="图片附件"></i>
</th>
<td class="by"><a href="forum-30-1.html">中文百合漫画区</a></td>
<td class="by">
<cite>
<a href="space-uid-244692.html" c="1">鹿角小黑猫</a>
</cite>
<em><span>2025-1-22</span></em>
</td>
<td class="num">
<a href="thread-553686-1-1.html" class="xi2">7</a>
<em>2987</em>
</td>
<td class="by">
<cite><a href="space-username-Shigatsu.html" c="1">Shigatsu</a></cite>
<em><a href="forum.php?mod=redirect&tid=553686&goto=lastpost#lastpost">2026-5-1 19:48</a></em>
</td>
</tr>
<tr>
<td class="icn">
```
一般情况下我们只需要匹配检索"thread-"到".html"不过可能会有重复，所以还需要去重
当然如果有更专业的flutter html解析工具，你尽管写到计划中去

以上就是message解析的一些要求了
还有就是我所依赖的网站是有搜索功能的，所以我还有实现搜索的功能
https://bbs.yamibo.com/search.php?mod=forum&mobile=2
这是搜索页面
响应如下
```
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta http-equiv="Cache-control" content="no-cache" />
<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no, minimum-scale=1.0, maximum-scale=1.0">
<meta name="format-detection" content="telephone=no" />
<title>搜索 -  百合会 -  手机版 - Powered by Discuz!</title>
<meta name="keywords" content="" />
<meta name="description" content=",百合会" />
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="百合会">
<meta name="google-site-verification" content="vr1rUdcW9ClwHHzhMeUAkNRMF9MhvoNO8P0fTNQqe7I" /><base href="https://bbs.yamibo.com/" />
<script type="text/javascript">var STYLEID = '19', STATICURL = 'static/', TPLTOUCHPATH = './template/oyeeh_com_baihe_f_x35/touch', IMGDIR = 'template/oyeeh_com_baihe_f_x35/img', VERHASH = 'JXg', charset = 'utf-8', discuz_uid = '597454', cookiepre = 'EeqY_2132_', cookiedomain = '', cookiepath = '/', showusercard = '1', attackevasive = '0', disallowfloat = 'newthread', creditnotice = '1|积分|点,6|对象|', defaultstyle = '', REPORTURL = 'aHR0cHM6Ly9iYnMueWFtaWJvLmNvbS9zZWFyY2gucGhwP21vZD1mb3J1bSZtb2JpbGU9Mg==', SITEURL = 'https://bbs.yamibo.com/', JSPATH = 'static/js/';</script>
<link rel="stylesheet" href="static/image/mobile/style.css?JXg" type="text/css" media="all">
<link rel="stylesheet" href="static/image/mobile/font/dzmicon.css?JXg" type="text/css" media="all">
<link rel="stylesheet" href="./template/oyeeh_com_baihe_f_x35/touch/common/common.css?JXg" type="text/css" media="all">
<link rel="manifest" href="./template/oyeeh_com_baihe_f_x35/touch/pwa/manifest.json">
<script src="static/js/mobile/jquery.min.js?JXg" type="text/javascript"></script>
<script src="static/js/mobile/common.js?JXg" type="text/javascript" charset="utf-8"></script>
<script src="static/js/swiper/swiper-bundle.min.js?JXg" type="text/javascript"></script>
<!-- <script src="./template/oyeeh_com_baihe_f_x35/touch/common/common-header.js?JXg" type="text/javascript"></script> -->
</head>
<body id="search" class="pg_forum">
<div id="header-padding"></div>

<div id="append_parent"></div><div class="header cl">
<div class="mz"><a href="javascript:history.back();"><i class="dm-c-left"></i></a></div>
<h2>帖子搜索</h2>
<div class="my"><a href="index.php?mobile=2"><i class="dm-house"></i></a></div>
</div><form class="searchform" method="post" autocomplete="off" action="search.php?mod=forum">
<input type="hidden" name="formhash" value="fe182126" />
<input type="hidden" name="srhfid" value=""><div class="search flex-box">
<input value="" autocomplete="off" class="mtxt flex" name="srchtxt" id="scform_srchtxt" value="" placeholder="搜索关键字">
<input type="hidden" name="searchsubmit" value="yes"><input type="submit" value="搜索" class="mbtn" id="scform_submit">
</div>
</form>

<div id="mask" style="display:none;"></div>
<div class="float-menu">
<div class="float-menu-item scroll-up-global">
<svg xmlns="http://www.w3.org/2000/svg" fill="currentColor" class="bi bi-chevron-up" viewBox="0 0 16 16">
<path fill-rule="evenodd" d="M7.646 4.646a.5.5 0 0 1 .708 0l6 6a.5.5 0 0 1-.708.708L8 5.707l-5.646 5.647a.5.5 0 0 1-.708-.708l6-6z"/>
</svg>
</div>
</div>
<div id="statcode" style="display:none;"><!-- Global site tag (gtag.js) - Google Analytics -->
<script async src="https://www.googletagmanager.com/gtag/js?id=UA-159997833-1"></script>
<script>
  window.dataLayer = window.dataLayer || [];
  function gtag(){dataLayer.push(arguments);}
  gtag('js', new Date());

  gtag('config', 'UA-159997833-1');
</script></div><div class="foot_height"></div>
<div class="foot-pwa">
<div class="foot-pwa-tip">添加到主屏幕以便捷访问论坛</div>
<div class="foot-pwa-btn">
<button type="button" class="foot-pwa-btn-yes">确定</button>
<button type="button" class="foot-pwa-btn-no">不用了</button>
</div>
</div>
<div class="foot flex-box">
<a href="index.php?mobile=2" class="flex">
<span class="foot-ico"><em class="ma"></em></span>
<span class="foot-txt">首页</span>
</a>
<a href="home.php?mod=space&amp;do=favorite&amp;mobile=2" class="flex">
<span class="foot-ico"><em class="md"></em></span>
<span class="foot-txt">收藏</span>
</a>
<!--
<a href="forum.php?mod=misc&amp;action=nav&amp;mobile=2" class="flex foot-post">
<span class="foot-ico"><em class="mc"></em></span>
<span class="foot-txt">发布</span>
</a>
-->
<a href="home.php?mod=space&amp;do=pm&amp;mobile=2" class="flex">
<span class="foot-ico"><em class="mb"></em></span>
<span class="foot-txt">消息</span>
</a>
<a href="home.php?mod=space&uid=597454&do=profile&mycenter=1&amp;mobile=2" class="flex">
<span class="foot-ico"><em class="me">
</em></span>
<span class="foot-txt">我的</span>
</a>
</div>
<script src="./template/oyeeh_com_baihe_f_x35/touch/common/common-footer.js?JXg" type="text/javascript"></script>
</body>
</html>
```
或者当知道formhash后直接两部进行搜索

第一步：发送 POST 请求

URL: [https://bbs.yamibo.com/search.php?mod=forum&searchsubmit=yes&mobile=2](https://bbs.yamibo.com/search.php?mod=forum&searchsubmit=yes&mobile=2)

POST Data: srchtxt=关键词&formhash=你的formhash

第二步：获取重定向后的内容

POST 成功后，服务器会返回一个 302 重定向到 search.php?mod=forum&searchid=123&...。

在这个重定向后的页面里，你就能拿到结果列表，返回的部分html如下
```
<li class="list">
<div class="threadlist_top cl">
<a href="home.php?mod=space&amp;uid=260328&amp;mobile=2" class="mimg"><img src="https://bbs.yamibo.com/uc_server/data/avatar/000/26/03/28_avatar_middle.jpg"></a>
<div class="muser">
<h3><a href="home.php?mod=space&amp;uid=260328&amp;mobile=2" class="mmc">朔月霏</a></h3>
<span class="mtime">2026-5-2 23:20</span>
</div>
</div>
<a href="forum.php?mod=viewthread&amp;tid=570616&amp;extra=&amp;mobile=2">
<div class="threadlist_tit cl">
<em >【提黄灯喵汉化组】[館山けーた]<strong><font color="#ff0000">百合</font></strong>情结 14</em>					
</div>
</a>
<a href="forum.php?mod=viewthread&amp;tid=570616&amp;extra=&amp;mobile=2"><div class="threadlist_mes cl"></div></a>
<div class="threadlist_foot cl">
<ul>
<li class="mr"><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">#中文百合漫画区</a></li>
<li><i class="dm-eye-fill"></i>88</li>
<li><i class="dm-chat-s-fill"></i>0</li>
</ul>
</div>
</li>
<li class="list">
<div class="threadlist_top cl">
<a href="home.php?mod=space&amp;uid=260328&amp;mobile=2" class="mimg"><img src="https://bbs.yamibo.com/uc_server/data/avatar/000/26/03/28_avatar_middle.jpg"></a>
<div class="muser">
<h3><a href="home.php?mod=space&amp;uid=260328&amp;mobile=2" class="mmc">朔月霏</a></h3>
<span class="mtime">2026-5-2 23:20</span>
</div>
</div>
<a href="forum.php?mod=viewthread&amp;tid=570615&amp;extra=&amp;mobile=2">
<div class="threadlist_tit cl">
<em >【提黄灯喵汉化组】[館山けーた]<strong><font color="#ff0000">百合</font></strong>情结 13</em>					
</div>
</a>
<a href="forum.php?mod=viewthread&amp;tid=570615&amp;extra=&amp;mobile=2"><div class="threadlist_mes cl"></div></a>
<div class="threadlist_foot cl">
<ul>
<li class="mr"><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">#中文百合漫画区</a></li>
<li><i class="dm-eye-fill"></i>95</li>
<li><i class="dm-chat-s-fill"></i>2</li>
</ul>
</div>
</li>
<li class="list">
<div class="threadlist_top cl">
<a href="home.php?mod=space&amp;uid=207314&amp;mobile=2" class="mimg"><img src="https://bbs.yamibo.com/uc_server/data/avatar/000/20/73/14_avatar_middle.jpg"></a>
<div class="muser">
<h3><a href="home.php?mod=space&amp;uid=207314&amp;mobile=2" class="mmc">甘木田</a></h3>
<span class="mtime">2026-5-2 21:06</span>
</div>
</div>
<a href="forum.php?mod=viewthread&amp;tid=570601&amp;extra=&amp;mobile=2">
<div class="threadlist_tit cl">
<em >【霜月汉化组】[蓬餅] 插足<strong><font color="#ff0000">百合</font></strong>的男人不如去死！？ 第 92 话</em>					
</div>
</a>
<a href="forum.php?mod=viewthread&amp;tid=570601&amp;extra=&amp;mobile=2">
<div class="none  threadlist_imgs cl">
<ul><li><img src="forum.php?mod=image&aid=1578458&size=125x115&key=df00da88ea8fe39c" class="vm" loading="lazy"></li>
<li><img src="forum.php?mod=image&aid=1578460&size=125x115&key=a24f4681069d1341" class="vm" loading="lazy"></li>
<li><img src="forum.php?mod=image&aid=1578461&size=125x115&key=c9f3a73b5b05158e" class="vm" loading="lazy"></li>
</ul>
</div>
</a>
<a href="forum.php?mod=viewthread&amp;tid=570601&amp;extra=&amp;mobile=2"><div class="threadlist_mes cl">【免责声明】
未经允许严禁转载、禁止无授权转载
禁止转载至Facebook、Twitter以及其他一切国际 ...</div></a>
<div class="threadlist_foot cl">
<ul>
<li class="mr"><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">#中文百合漫画区</a></li>
<li><i class="dm-eye-fill"></i>257</li>
<li><i class="dm-chat-s-fill"></i>4</li>
</ul>
</div>
</li>
<li class="list">
<div class="threadlist_top cl">
<a href="home.php?mod=space&amp;uid=664313&amp;mobile=2" class="mimg"><img src="https://bbs.yamibo.com/uc_server/data/avatar/000/66/43/13_avatar_middle.jpg"></a>
<div class="muser">
<h3><a href="home.php?mod=space&amp;uid=664313&amp;mobile=2" class="mmc">Yuriちゃん</a></h3>
<span class="mtime">2026-5-2 20:55</span>
</div>
</div>
<a href="forum.php?mod=viewthread&amp;tid=570600&amp;extra=&amp;mobile=2">
<div class="threadlist_tit cl">
<em >【夢怜龍華组】[上村なびあ]<strong><font color="#ff0000">百合</font></strong>盛开·三角关系，被病娇青梅和真<strong><font color="#ff0000">百合</font></strong>留学生同时追求，我的<strong><font color="#ff0000">百合</font></strong>花园大盛开！？（ゆりさき・とらいあんぐる ヤンデレ幼なじみとガチユリ留学生に求愛されて、<strong><font color="#ff0000">百合</font></strong>の花園が満開です！？）第2话</em>					
</div>
</a>
```

最后还有一个收藏页要实现，应该是要再Tab栏中新开一个叫"收藏"
目前本项目实现的是本地收藏，不过实际上这是占位符，真正的实现还需要网页上的收藏，不过我们可以做一些缓存设计
收藏对应的网页的api为
https://bbs.yamibo.com/api/mobile/index.php?module=myfavthread&version=4&page=1
因为有page所以可能有多页
返回的json的 "Variables"中有
```
  "list":[
            {
                "favid":"2566038",
                "uid":"597454",
                "id":"570311",
                "idtype":"tid",
                "spaceuid":"0",
                "title":"【绿茶汉化组】[秋津貴央]小舞给大姐姐的投食日记。 第31话",
                "description":"手机收藏",
                "dateline":"1777176709",
                "icon":"<img src="static/image/feed/thread.gif" alt="thread" class="t" /> ",
                "url":"forum.php?mod=viewthread&tid=570311",
                "replies":"10",
                "author":"xthyme"
            },
            {
                "favid":"2559822",
                "uid":"597454",
                "id":"570140",
                "idtype":"tid",
                "spaceuid":"0",
                "title":"【提灯喵汉化组】[ヒジキ]契约姐妹 28",
                "description":"手机收藏",
                "dateline":"1776770702",
                "icon":"<img src="static/image/feed/thread.gif" alt="thread" class="t" /> ",
                "url":"forum.php?mod=viewthread&tid=570140",
                "replies":"35",
                "author":"tidengmiao"
            },
            {
                "favid":"2547743",
                "uid":"597454",
                "id":"504403",
                "idtype":"tid",
                "spaceuid":"0",
                "title":"【提灯喵汉化组】[鈴木先輩]半夜邻叫 最终话",
                "description":"手机收藏",
                "dateline":"1775976196",
                "icon":"<img src="static/image/feed/thread.gif" alt="thread" class="t" /> ",
                "url":"forum.php?mod=viewthread&tid=504403",
                "replies":"96",
                "author":"tidengmiao"
            },
```

因为原版收藏中没有fid，导致我们解析的话可能要访问每一个收藏的帖子，
所以应该将访问过的收藏的fid缓存起来，方便匹配

我想实现的最终目的是非常灵活的联动，比如漫画版块的漫画的详细预览中应该有更新按钮
更新会调用搜索功能来根据漫画的名字来搜索，然后匹配名字和fid，而且排名靠前的帖子，进入后解析message然后根据我们实现的规则来解析跳转链接的到之前的话，然后更新对应漫画的详细预览。（不过要注意限制，10内只能进行一次搜索）

然后漫画版块的列表应该取决与我们实现的收藏版块的缓存，因为缓存才有储存收藏的帖子的fid，然后
漫画版块如果发现有自己没有加入的漫画就加入后刷新，（也就是漫画版块和收藏版块都有缓存，漫画版块的缓存依赖于收藏版块的缓存）

然后我还想实现正在的备份，备份应包括包括收藏中的信息，因为单纯的网页的收藏列表没有帖子对应的fid，导致如果要解析可能要访问全部的收藏，所以备份和缓存应该记住收藏的帖子对应的fid，进行更新时，只需要访问为缓存的帖子
以及漫画的缓存，以及预留的小说缓存
因为我感觉备份是我迭代的关键，当我更新时，如果我没实现备份，我的用户就要又重新开始

最后我应该会实现小说版块和完善论坛功能不过这都是后话了

请仔细阅读项目的代码，和以上内容，你给我写一个尽可能详细的分阶段实现搜索收藏联动.md这个文档放到当前目录下的docs文件夹，一定一定要尽可能的详细，因为这是我项目稳步推进的关键，实现一定给出结构化工程化的详尽方案这对我真的很重要拜托了。