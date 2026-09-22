// Synthetic, public-content-free fragments matching Discuz mobile templates.
// Keep empty interaction containers and comment pagination as template facts;
// navigation does not fetch comment pages or depend on an interaction anchor.
const mobilePostLocationHtml = '''
<html><head><link rel="canonical" href="/thread-100-3-1.html"></head>
<body id="forum"><div class="viewthread">
  <h2 class="view_tit">Fixture thread</h2>
  <div class="plc" id="pid200"><div class="display">
    <div class="authi"><div class="mtit"><span class="z">
      <a href="home.php?mod=space&amp;uid=10">Fixture author</a>
    </span><span class="y">41#</span></div></div>
    <div class="message"><p>Chapter opening.</p>
      <p>Long body segment one.</p><p>Long body segment two.</p>
      <p>Long body segment three.</p><p>Chapter ending.</p>
    </div>
    <div id="comment_200"></div><div id="ratelog_200"></div>
  </div></div>
</div><div class="pg"><strong>3</strong></div></body></html>
''';

const mobilePostMissingHtml = '''
<html><head><link rel="canonical" href="/thread-100-1-1.html"></head>
<body id="forum"><div class="viewthread"><div class="plc" id="pid199">
  <div class="message">Thread home, target absent.</div>
</div></div><div class="pg"><strong>1</strong></div></body></html>
''';

const desktopPostLocationHtml = '''
<html><body id="nv_forum"><div id="post_200"><table id="pid200">
  <tr><td class="t_f" id="postmessage_200">Different pagination.</td></tr>
</table></div><div class="pg"><strong>7</strong></div></body></html>
''';

const loginRequiredPostHtml = '''
<html><body><form action="member.php?mod=logging&amp;action=login">
  <input name="username"><input name="password" type="password">
</form></body></html>
''';

const commentPaginationHtml = '''
<div id="comment_200"><div id="dumppage"></div><div class="pgs cl"><div class="page">
  <a href="javascript:;" class="nxt" onclick="ajaxget('forum.php?mod=misc&action=commentmore&tid=100&pid=200&page=2', 'comment_200')">Next</a>
</div></div></div>
''';

final longMobilePostLocationHtml = mobilePostLocationHtml.replaceFirst(
  '<p>Long body segment one.</p>',
  List.filled(400, '<p>Synthetic long chapter paragraph.</p>').join(),
);
