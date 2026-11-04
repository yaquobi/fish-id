import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// يرسل إيميل HTML (مع نسخة نصية). يرمي خطأ إذا ما وصل للخادم.
typedef SendMail = Future<void> Function({required String to, required String subject, required String html, required String text});

/// مرسل SMTP صغير بدون مكتبات، على TLS مباشر (منفذ 465).
/// مع Google Workspace نستخدم smtp-relay.gmail.com بإذن عنوان السيرفر (بدون كلمة سر)،
/// أو [user] و [pass] لأي خادم ثاني.
class Mailer {
  Mailer({required this.host, this.port = 465, required this.from, this.fromName = '', this.user = '', this.pass = '', this.helo = 'hawat.id'});

  final String host;
  final int port;
  final String from;
  final String fromName;
  final String user;
  final String pass;
  final String helo;

  static String _b64(String s) => base64.encode(utf8.encode(s));
  static String _header(String s) => s.codeUnits.every((c) => c < 128) ? s : '=?UTF-8?B?${_b64(s)}?=';
  static String _wrap(String s) => [for (var i = 0; i < s.length; i += 76) s.substring(i, i + 76 > s.length ? s.length : i + 76)].join('\r\n');

  /// نص الرسالة كامل بصيغة MIME (مفصول عشان نختبره).
  String message({required String to, required String subject, required String html, required String text, DateTime? now, String? boundary}) {
    final b = boundary ?? 'b${DateTime.now().microsecondsSinceEpoch}';
    final date = HttpDate.format(now ?? DateTime.now()).replaceFirst('GMT', '+0000');
    return [
      'From: ${fromName.isEmpty ? from : '${_header(fromName)} <$from>'}',
      'To: $to',
      'Subject: ${_header(subject)}',
      'Date: $date',
      'Message-ID: <${DateTime.now().microsecondsSinceEpoch}.${to.hashCode.abs()}@$helo>',
      'MIME-Version: 1.0',
      'Content-Type: multipart/alternative; boundary="$b"',
      '',
      '--$b',
      'Content-Type: text/plain; charset=UTF-8',
      'Content-Transfer-Encoding: base64',
      '',
      _wrap(_b64(text)),
      '--$b',
      'Content-Type: text/html; charset=UTF-8',
      'Content-Transfer-Encoding: base64',
      '',
      _wrap(_b64(html)),
      '--$b--',
      '',
    ].join('\r\n');
  }

  Future<void> send({required String to, required String subject, required String html, required String text}) async {
    if (to.contains(RegExp(r'[\r\n<>,]'))) throw const FormatException('bad address');
    final socket = await SecureSocket.connect(host, port, timeout: const Duration(seconds: 15));
    final lines = _Lines(socket);
    try {
      await lines.expect(220);
      socket.write('EHLO $helo\r\n');
      await lines.expect(250);
      if (user.isNotEmpty) {
        socket.write('AUTH PLAIN ${base64.encode(utf8.encode('\u0000$user\u0000$pass'))}\r\n');
        await lines.expect(235);
      }
      socket.write('MAIL FROM:<$from>\r\n');
      await lines.expect(250);
      socket.write('RCPT TO:<$to>\r\n');
      await lines.expect(250);
      socket.write('DATA\r\n');
      await lines.expect(354);
      // سطر يبدأ بنقطة لازم يتضاعف (ما يصير مع base64، بس احتياط).
      socket.write('${message(to: to, subject: subject, html: html, text: text).replaceAll('\r\n.', '\r\n..')}\r\n.\r\n');
      await lines.expect(250);
      socket.write('QUIT\r\n');
    } finally {
      await socket.close().catchError((_) => socket);
      socket.destroy();
    }
  }
}

/// يقرا ردود SMTP سطر سطر (الرد الأخير من مجموعة سطور فيه مسافة بعد الرقم).
class _Lines {
  _Lines(Socket s) {
    s.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).listen(_queue.add, onDone: _queue.close, onError: (_) => _queue.close());
  }
  final _queue = StreamController<String>();
  late final _it = StreamIterator(_queue.stream);

  Future<void> expect(int code) async {
    while (true) {
      if (!await _it.moveNext().timeout(const Duration(seconds: 20))) throw const SocketException('smtp closed');
      final l = _it.current;
      if (l.length >= 4 && l[3] == '-') continue;
      if (!l.startsWith('$code')) throw SocketException('smtp: $l');
      return;
    }
  }
}
