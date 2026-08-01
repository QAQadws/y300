import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/services/thread_detail_snapshot_codec.dart';

void main() {
  group('ThreadDetailData.fromVariables', () {
    test('parses typeid from thread payload', () {
      final data = ThreadDetailData.fromVariables(<String, dynamic>{
        'fid': '30',
        'ppp': '20',
        'thread': <String, dynamic>{
          'tid': '100',
          'typeid': '398',
          'subject': '测试漫画',
          'author': 'alice',
          'replies': '0',
          'views': '12',
        },
        'postlist': const <Map<String, dynamic>>[],
      }, page: 1);

      expect(data.fid, '30');
      expect(data.typeid, '398');
    });

    test('falls back to variables typeid when thread typeid is absent', () {
      final data = ThreadDetailData.fromVariables(<String, dynamic>{
        'fid': '49',
        'typeid': '293',
        'thread': <String, dynamic>{'tid': '101', 'subject': '测试小说'},
        'postlist': const <Map<String, dynamic>>[],
      }, page: 1);

      expect(data.typeid, '293');
    });

    test('keeps raw attachment metadata from postlist', () {
      final data = ThreadDetailData.fromVariables(<String, dynamic>{
        'fid': '30',
        'thread': <String, dynamic>{
          'tid': '476706',
          'subject': 'attachment comic',
        },
        'postlist': <Map<String, dynamic>>[
          <String, dynamic>{
            'pid': '39089696',
            'author': 'cc01205',
            'authorid': '246572',
            'message': 'text only',
            'number': '1',
            'first': '1',
            'dateline': '2018-2-16 00:29',
            'attachments': <String, dynamic>{
              '625902': <String, dynamic>{
                'aid': '625902',
                'filename': 'Screenshot.jpg',
                'attachment': '201802/16/002909v4kga3k6tkh4mlap.jpg',
                'url': 'data/attachment/forum/',
                'attachimg': '1',
                'ext': 'jpg',
              },
              '625903': <String, dynamic>{
                'aid': '625903',
                'filename': 'archive.zip',
                'attachment': '201802/16/archive.zip',
                'url': 'data/attachment/forum/',
                'attachimg': '0',
                'ext': 'zip',
              },
            },
          },
        ],
      }, page: 1);

      final attachments = data.posts.single.attachmentImages;
      expect(attachments.length, 2);
      expect(attachments.first.aid, '625902');
      expect(attachments.first.url, 'data/attachment/forum/');
      expect(
        attachments.first.attachment,
        '201802/16/002909v4kga3k6tkh4mlap.jpg',
      );
      expect(attachments.first.attachimg, '1');
      expect(attachments.first.ext, 'jpg');
      expect(attachments.last.aid, '625903');
      expect(attachments.last.attachment, '201802/16/archive.zip');
      expect(attachments.last.ext, 'zip');
    });
  });

  group('ThreadDetailSnapshotCodec', () {
    test('round trips parsed thread detail data', () {
      final source = ThreadDetailData(
        tid: '572529',
        fid: '33',
        typeid: '410',
        typeName: '理性探讨',
        forumName: '杂谈区',
        forumUrl: 'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=33',
        subject: '测试帖子',
        author: 'alice',
        replies: 3,
        views: 12,
        currentPage: 2,
        perPage: 20,
        lastPage: 6,
        previousPageUrl: 'prev',
        nextPageUrl: 'next',
        reverseOrderUrl: 'reverse',
        onlyAuthorUrl: 'author',
        favoriteUrl: 'favorite',
        shareUrl: 'share',
        homeUrl: 'home',
        desktopUrl: 'desktop',
        posts: <ThreadPost>[
          ThreadPost(
            pid: '41562047',
            author: 'alice',
            authorId: '10',
            message: '<p>正文</p>',
            number: 1,
            isFirst: true,
            dateline: '2026-6-20 10:00',
            avatarUrl: 'avatar',
            replyUrl: 'reply',
            editUrl:
                'https://bbs.yamibo.com/forum.php?mod=post&action=edit&fid=33&tid=572529&pid=41562047',
            rateUrl: 'rate',
            commentUrl: 'comment',
            rateSummary: '+2',
            ratingSummary: const ThreadPostRatingSummary(
              participantText: '1 人评分',
              scoreText: '+2',
              viewAllUrl: 'all-ratings',
              ratings: <ThreadPostRating>[
                ThreadPostRating(
                  userName: 'bob',
                  userId: '11',
                  avatarUrl: 'bob-avatar',
                  score: '+2',
                  reason: '好',
                  dateline: '2026-7-24 10:00',
                ),
              ],
            ),
            poll: const ThreadPoll(
              isMultipleChoice: true,
              canVote: false,
              maxChoices: 3,
              summary: '多选投票',
              deadlineText: '距结束还有 1 天',
              actionUrl: 'poll',
              formHash: 'hash',
              statusText: '您已经投过票',
              options: <ThreadPollOption>[
                ThreadPollOption(
                  id: '1',
                  label: '选项',
                  voteCount: 7,
                  percent: 70,
                  colorHex: '#E92725',
                ),
              ],
            ),
            tagLinks: const <ThreadPostTagLink>[
              ThreadPostTagLink(label: 'tag', url: 'tag-url', tagId: '20674'),
            ],
            comments: const <ThreadPostCommentEntry>[
              ThreadPostCommentEntry(
                author: 'carol',
                authorId: '12',
                authorUrl: 'carol-url',
                avatarUrl: 'carol-avatar',
                message: '点评',
                dateline: '刚刚',
              ),
            ],
            attachmentImages: const <ForumPostAttachmentImage>[
              ForumPostAttachmentImage(
                aid: '1',
                url: 'data/attachment/forum/',
                attachment: 'a.jpg',
                filename: 'a.jpg',
                attachimg: '1',
                ext: 'jpg',
              ),
            ],
          ),
        ],
      );
      const codec = ThreadDetailSnapshotCodec();

      final decoded = codec.decode(codec.encode(source));

      expect(decoded.subject, source.subject);
      expect(decoded.posts.single.pid, '41562047');
      expect(decoded.posts.single.editUrl, source.posts.single.editUrl);
      expect(decoded.posts.single.poll!.options.single.colorHex, '#E92725');
      expect(decoded.posts.single.ratingSummary!.ratings.single.reason, '好');
      expect(
        decoded.posts.single.ratingSummary!.ratings.single.dateline,
        '2026-7-24 10:00',
      );
      expect(decoded.posts.single.comments.single.message, '点评');
      expect(decoded.posts.single.tagLinks.single.tagId, '20674');
      expect(decoded.posts.single.attachmentImages.single.attachment, 'a.jpg');
    });

    test('decodes snapshots written before editUrl existed', () {
      const codec = ThreadDetailSnapshotCodec();
      final decoded = codec.decode(<String, Object?>{
        'tid': '572529',
        'fid': '33',
        'subject': '旧缓存',
        'author': 'alice',
        'posts': <Object?>[
          <String, Object?>{
            'pid': '41562047',
            'author': 'alice',
            'authorId': '10',
            'message': '正文',
            'number': 1,
            'isFirst': true,
            'dateline': '2026-6-20 10:00',
          },
        ],
      });

      expect(decoded.posts.single.editUrl, isNull);
    });
  });
}
