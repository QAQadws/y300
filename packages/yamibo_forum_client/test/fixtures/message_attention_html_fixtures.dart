// Synthetic, account-free public chrome modeled on Discuz / Yamibo templates.
// These fixtures deliberately do not read local forum source trees.

String attentionHtmlDocument(
  String body, {
  String viewerUserId = '42',
  String extraHead = '',
}) =>
    '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <script>var discuz_uid = '$viewerUserId';</script>
  $extraHead
</head>
<body>
$body
</body>
</html>
''';

String mobileAttentionFooter({
  bool messageDot = false,
  bool profileDot = false,
  bool defaultTouchProfileOnly = false,
  String messageHref = 'home.php?mod=space&amp;do=pm',
  String profileHref =
      'home.php?mod=space&amp;uid=42&amp;do=profile&amp;mycenter=1',
}) =>
    '''
<div class="foot flex-box">
  <a href="forum.php" class="flex mon">
    <span class="foot-ico"><em class="ma"></em></span>
    <span class="foot-txt">Forum</span>
  </a>
  <a href="${defaultTouchProfileOnly ? 'portal.php' : messageHref}" class="flex">
    <span class="foot-ico"><em class="mb">${!defaultTouchProfileOnly && messageDot ? '<i class="ico_msg"></i>' : ''}</em></span>
    <span class="foot-txt">${defaultTouchProfileOnly ? 'Portal' : 'Messages'}</span>
  </a>
  <a href="$profileHref" class="flex">
    <span class="foot-ico"><em class="me">${profileDot ? '<i class="ico_msg"></i>' : ''}</em></span>
    <span class="foot-txt">My profile</span>
  </a>
</div>
''';

String mobileAttentionHtml({
  bool messageDot = false,
  bool profileDot = false,
  bool defaultTouchProfileOnly = false,
  bool includeFooter = true,
  String content = '<div id="ct"><p>Public forum content.</p></div>',
  String viewerUserId = '42',
  String extraHead = '',
  String messageHref = 'home.php?mod=space&amp;do=pm',
  String profileHref =
      'home.php?mod=space&amp;uid=42&amp;do=profile&amp;mycenter=1',
}) => attentionHtmlDocument(
  '''
$content
${includeFooter ? mobileAttentionFooter(messageDot: messageDot, profileDot: profileDot, defaultTouchProfileOnly: defaultTouchProfileOnly, messageHref: messageHref, profileHref: profileHref) : ''}
<script src="home.php?mod=spacecp&amp;ac=pm&amp;op=checknewpm"></script>
''',
  viewerUserId: viewerUserId,
  extraHead: extraHead,
);

String desktopAttentionMenu({bool privateMessageDot = false}) =>
    '''
<ul id="myprompt_menu" class="p_pop" style="display: none;">
  <li>
    <a href="home.php?mod=space&amp;do=pm" id="pm_ntc">
      <em class="${privateMessageDot ? 'prompt_news' : 'prompt_news_0'}"></em>Messages
    </a>
  </li>
  <li class="ignore_noticeli">
    <a href="javascript:;"><em class="ignore_notice"></em></a>
  </li>
</ul>
''';

String desktopAttentionTop({
  bool privateMessageDot = false,
  bool notificationDot = false,
  String notificationSuffix = '',
  bool defaultTemplate = false,
}) {
  final links =
      '''
  <li id="avtnav" class="y"><a href="home.php?mod=space&amp;uid=42">My profile</a></li>
  <li><a href="home.php?mod=space&amp;do=pm" id="pm_ntc"${privateMessageDot ? ' class="new"' : ''}>Messages</a></li>
  <li><a href="home.php?mod=space&amp;do=notice" id="myprompt" class="a showmenu${notificationDot ? ' new' : ''}">Notifications$notificationSuffix</a><span id="myprompt_check"></span></li>
''';
  if (defaultTemplate) {
    return '<div id="hd"><div class="wp"><div id="um">$links</div></div></div>';
  }
  return '''
<div class="oyheader">
  <div class="header-stackup">
    <div class="wp cl"><ul class="header-tool y">$links</ul></div>
  </div>
</div>
''';
}

String desktopAttentionHtml({
  bool privateMessageDot = false,
  bool notificationDot = false,
  bool includeMenu = true,
  bool? menuPrivateMessageDot,
  String notificationSuffix = '',
  bool defaultTemplate = false,
  String content = '<div id="ct"><p>Public forum content.</p></div>',
}) => attentionHtmlDocument('''
${includeMenu ? desktopAttentionMenu(privateMessageDot: menuPrivateMessageDot ?? privateMessageDot) : ''}
${desktopAttentionTop(privateMessageDot: privateMessageDot, notificationDot: notificationDot, notificationSuffix: notificationSuffix, defaultTemplate: defaultTemplate)}
$content
''');
