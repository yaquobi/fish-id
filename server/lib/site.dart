import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// إحصائية صفحة hawat.id لتقرير تليجرام: الزيارات ومن وين جت، والزوار المختلفين، والروابط اللي انضغطت.
/// ما نحفظ IP ولا أي بيانات شخصية: الزائر يتعرّف ببصمة رقمية من IP والمتصفح تبقى في الذاكرة لنفس اليوم بس،
/// والملف `site.json` في مجلد الحسابات فيه أعداد لكل يوم بتوقيت السعودية (آخر 120 يوم).
class SiteStats {
  SiteStats._(this.dir, this._days);

  final String dir;
  final Map<String, Map<String, dynamic>> _days;

  /// مصادر الزيارة اللي نعدّها بأسمائها، والباقي «other».
  static const sources = ['fb_ad', 'facebook', 'instagram', 'google', 'bing', 'tiktok', 'snapchat', 'x', 'whatsapp', 'telegram', 'ksafish', 'direct'];

  /// الروابط اللي نعدّ ضغطاتها (data-track في الصفحة).
  static const targets = {
    'facebook',
    'instagram',
    'x',
    'notify_button',
    'waitlist_signup',
    'store',
    'play_testing',
    'ksafish',
    'email',
    'download_button',
    'pricing_button',
  };

  static const _keep = 120;
  static const _perVisitorDay = 60;
  static final _bots = RegExp(r'bot|crawl|spider|slurp|preview|facebookexternalhit|headless|lighthouse', caseSensitive: false);

  /// بصمات زوار اليوم الحالي وعدد أحداث كل واحد.
  String _today = '';
  final _seen = <int, int>{};
  Timer? _pending;

  static SiteStats open(String dir) {
    final f = File('$dir/site.json');
    final m = f.existsSync()
        ? (jsonDecode(f.readAsStringSync()) as Map).map((k, v) => MapEntry('$k', (v as Map).cast<String, dynamic>()))
        : <String, Map<String, dynamic>>{};
    return SiteStats._(dir, m);
  }

  static String dayOf(DateTime now) => now.toUtc().add(const Duration(hours: 3)).toIso8601String().substring(0, 10);

  /// يحوّل utm_source أو اسم الموقع اللي جا منه الزائر لواحد من [sources].
  static String sourceOf(String raw) {
    final s = raw.toLowerCase().trim();
    if (s.isEmpty || s == 'direct' || s == 'hawat.id' || s.endsWith('.hawat.id')) return 'direct';
    if (s == 'fb_ad' || s == 'fbad' || s == 'meta_ad' || s == 'ig_ad') return 'fb_ad';
    bool has(String w) => s == w || s.contains('$w.') || s.contains('.$w') || s.startsWith(w);
    if (has('instagram') || s == 'ig') return 'instagram';
    if (has('facebook') || s == 'fb' || s.endsWith('fb.com') || s.endsWith('fb.me')) return 'facebook';
    if (has('google')) return 'google';
    if (has('bing')) return 'bing';
    if (has('tiktok')) return 'tiktok';
    if (has('snapchat') || s == 'snap') return 'snapchat';
    if (s == 'x' || s == 't.co' || has('twitter') || s == 'x.com') return 'x';
    if (has('whatsapp') || s == 'wa.me' || s == 'wa') return 'whatsapp';
    if (has('telegram') || s == 't.me') return 'telegram';
    if (has('ksafish')) return 'ksafish';
    return 'other';
  }

  /// يسجّل حدث من الصفحة: `{"e": "visit", "src": ...}` أو `{"e": "click", "t": ...}`. يرجّع false إذا تجاهله.
  bool record(Map body, {required String ip, required String agent, required DateTime now}) {
    if (_bots.hasMatch(agent)) return false;
    final day = dayOf(now);
    if (day != _today) {
      _today = day;
      _seen.clear();
    }
    final who = Object.hash(ip, agent);
    final n = _seen[who] ?? 0;
    if (n >= _perVisitorDay) return false;
    final d = _days.putIfAbsent(day, () => {'visits': 0, 'unique': 0, 'src': <String, dynamic>{}, 'clicks': <String, dynamic>{}, 'hours': <String, dynamic>{}});
    void bump(String group, String key) {
      final g = ((d[group] as Map?) ?? {}).cast<String, dynamic>();
      g[key] = ((g[key] as num?) ?? 0) + 1;
      d[group] = g;
    }

    switch (body['e']) {
      case 'visit':
        d['visits'] = (d['visits'] as num) + 1;
        if (!_seen.containsKey(who)) d['unique'] = (d['unique'] as num) + 1;
        bump('src', sourceOf('${body['src'] ?? ''}'));
        // ساعة الزيارة بتوقيت السعودية، عشان نعرف وقت الذروة ونوقّت الإعلانات عليه.
        bump('hours', now.toUtc().add(const Duration(hours: 3)).hour.toString().padLeft(2, '0'));
      case 'click':
        final t = '${body['t']}';
        if (!targets.contains(t)) return false;
        bump('clicks', t);
      default:
        return false;
    }
    _seen[who] = n + 1;
    _saveSoon();
    return true;
  }

  /// مجموع الأيام من [from] إلى [to] (شاملة، بصيغة yyyy-mm-dd).
  Map<String, dynamic> total(String from, String to) {
    var visits = 0, unique = 0;
    final src = <String, int>{}, clicks = <String, int>{}, hours = <String, int>{};
    for (final e in _days.entries) {
      if (e.key.compareTo(from) < 0 || e.key.compareTo(to) > 0) continue;
      visits += (e.value['visits'] as num).toInt();
      unique += (e.value['unique'] as num).toInt();
      (e.value['src'] as Map).forEach((k, v) => src['$k'] = (src['$k'] ?? 0) + (v as num).toInt());
      (e.value['clicks'] as Map).forEach((k, v) => clicks['$k'] = (clicks['$k'] ?? 0) + (v as num).toInt());
      ((e.value['hours'] as Map?) ?? {}).forEach((k, v) => hours['$k'] = (hours['$k'] ?? 0) + (v as num).toInt());
    }
    return {'visits': visits, 'unique': unique, 'src': src, 'clicks': clicks, 'hours': hours};
  }

  /// كل يوم من آخر [days] يوم (الأقدم أول): الزيارات والزوار والضغطات، للوحة الأدمن.
  List<Map<String, dynamic>> series(int days, DateTime now) => [
    for (var i = days - 1; i >= 0; i--)
      () {
        final key = dayOf(now.subtract(Duration(days: i)));
        final t = total(key, key);
        return {'key': key, 'visits': t['visits'], 'unique': t['unique'], 'clicks': (t['clicks'] as Map).values.fold<int>(0, (a, b) => a + (b as int))};
      }(),
  ];

  /// ملخص لوحة الأدمن: اليوم وآخر 7 و30 يوم، والسلسلة اليومية.
  Map<String, dynamic> view(DateTime now) {
    final today = dayOf(now);
    return {
      'today': total(today, today),
      'week': total(dayOf(now.subtract(const Duration(days: 6))), today),
      'month': total(dayOf(now.subtract(const Duration(days: 29))), today),
      'daily': series(30, now),
    };
  }

  static const _srcNames = {
    'fb_ad': 'إعلان فيسبوك/إنستغرام',
    'facebook': 'فيسبوك',
    'instagram': 'إنستغرام',
    'google': 'قوقل',
    'bing': 'بينق',
    'tiktok': 'تيك توك',
    'snapchat': 'سناب',
    'x': 'إكس',
    'whatsapp': 'واتساب',
    'telegram': 'تليجرام',
    'ksafish': 'الموسوعة',
    'direct': 'مباشر',
    'other': 'غيره',
  };
  static String sourceName(String k) => _srcNames[k] ?? k;

  static const _clickNames = {
    'download_button': 'زر حمّل التطبيق',
    'store': 'أزرار المتاجر',
    'play_testing': 'رابط تجربة أندرويد',
    'pricing_button': 'زر الأسعار',
    'facebook': 'أيقونة فيسبوك',
    'instagram': 'أيقونة إنستغرام',
    'x': 'أيقونة إكس',
    'notify_button': 'زر بلّغني',
    'waitlist_signup': 'سجلوا في بلّغني',
    'ksafish': 'روابط الموسوعة',
    'email': 'تواصل معنا',
  };

  /// سطور تقرير تليجرام: اليوم، وآخر 7 أيام.
  List<String> summaryLines(DateTime now) {
    final today = dayOf(now);
    final week = dayOf(now.subtract(const Duration(days: 6)));
    final d = total(today, today), w = total(week, today);
    String top(Map m, Map<String, String> names) {
      final list = (m.cast<String, int>().entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
      return list.isEmpty ? 'لا شيء' : list.map((e) => '${names[e.key] ?? e.key} ${e.value}').join('، ');
    }

    final clicks = (d['clicks'] as Map).values.fold<int>(0, (a, b) => a + (b as int));
    return [
      '',
      '🌐 موقع hawat.id اليوم: ${d['visits']} زيارة من ${d['unique']} زائر',
      'من وين: ${top(d['src'] as Map, _srcNames)}',
      'الضغطات: $clicks${clicks == 0 ? '' : ' (${top(d['clicks'] as Map, _clickNames)})'}',
      'آخر 7 أيام: ${w['visits']} زيارة، ${w['unique']} زائر، ${(w['clicks'] as Map).values.fold<int>(0, (a, b) => a + (b as int))} ضغطة',
    ];
  }

  /// الكتابة على الملف تتجمع كل 10 ثواني عشان كثرة الزيارات ما تكتب على القرص كل مرة.
  void _saveSoon() {
    if (_pending?.isActive ?? false) return;
    _pending = Timer(const Duration(seconds: 10), () => unawaited(save()));
  }

  Future<void> _queue = Future.value();

  Future<void> save() {
    final keys = _days.keys.toList()..sort();
    for (final k in keys.take(keys.length > _keep ? keys.length - _keep : 0)) {
      _days.remove(k);
    }
    final text = jsonEncode(_days);
    return _queue = _queue.then((_) async {
      final tmp = File('$dir/site.json.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename('$dir/site.json');
    });
  }
}
