import 'dart:convert';
import 'dart:io';

import 'package:fish_id_server/accounts.dart';
import 'package:fish_id_server/app.dart';
import 'package:fish_id_server/site.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  // 10 مساءً بتوقيت السعودية.
  var t = DateTime.utc(2026, 10, 30, 19);
  setUp(() => dir = Directory.systemTemp.createTempSync('site'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<Response> track(FishIdApp app, Map body, {String ip = '1.2.3.4', String agent = 'Mozilla/5.0 iPhone'}) async =>
      app.handler(Request('POST', Uri.parse('http://x/api/track'), body: jsonEncode(body), headers: {'x-forwarded-for': '$ip, 10.0.0.1', 'user-agent': agent}));

  test('sources from utm, ad click ids and referrers', () {
    expect(SiteStats.sourceOf('fb_ad'), 'fb_ad');
    expect(SiteStats.sourceOf('l.instagram.com'), 'instagram');
    expect(SiteStats.sourceOf('m.facebook.com'), 'facebook');
    expect(SiteStats.sourceOf('www.google.com.sa'), 'google');
    expect(SiteStats.sourceOf('t.co'), 'x');
    expect(SiteStats.sourceOf(''), 'direct');
    expect(SiteStats.sourceOf('hawat.id'), 'direct');
    expect(SiteStats.sourceOf('example.org'), 'other');
  });

  test('visits, unique visitors and clicks go into the daily summary and survive a restart', () async {
    final site = SiteStats.open(dir.path);
    final app = FishIdApp(identify: null, accounts: AccountStore.open(dir.path), site: site, clock: () => t);
    expect((await track(app, {'e': 'visit', 'src': 'fb_ad'})).statusCode, 204);
    await track(app, {'e': 'visit', 'src': 'fb_ad'});
    await track(app, {'e': 'visit', 'src': 'l.instagram.com'}, ip: '5.6.7.8');
    await track(app, {'e': 'visit', 'src': ''}, agent: 'Googlebot/2.1');
    await track(app, {'e': 'click', 't': 'download_button'});
    await track(app, {'e': 'click', 't': 'instagram'}, ip: '5.6.7.8');
    await track(app, {'e': 'click', 't': 'javascript:alert(1)'});
    expect((await app.handler(Request('POST', Uri.parse('http://x/api/track'), body: 'not json'))).statusCode, 204);

    final day = site.total('2026-10-30', '2026-10-30');
    expect(day['visits'], 3);
    expect(day['unique'], 2);
    expect(day['src'], {'fb_ad': 2, 'instagram': 1});
    expect(day['clicks'], {'download_button': 1, 'instagram': 1});

    final summary = app.dailySummary(t)!;
    expect(summary, contains('hawat.id اليوم: 3 زيارة من 2 زائر'));
    expect(summary, contains('إعلان فيسبوك/إنستغرام 2'));
    expect(summary, contains('الضغطات: 2'));

    await site.save();
    t = t.add(const Duration(days: 1));
    final again = SiteStats.open(dir.path);
    expect(again.total('2026-10-24', '2026-10-31')['visits'], 3);
    expect(again.summaryLines(t).join('\n'), contains('آخر 7 أيام: 3 زيارة'));
  });
}
