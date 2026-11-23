import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

/// Must stay identical to normalize in tools/build_db.py
String normalizeAr(String s) {
  s = s.replaceAll(RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06ED\u0640]'), '');
  s = s.replaceAll(RegExp(r'[إأآٱ]'), 'ا').replaceAll('ى', 'ي').replaceAll('ة', 'ه');
  s = s.replaceAll(RegExp(r'[^\u0621-\u064A\u0660-\u0669a-zA-Z0-9\s]'), ' ');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Builds an FTS5 MATCH expression: every query term matches with or without
/// the "ال" prefix, so «النيات» also finds «بالنيات» and «نيات».
/// Terms are ANDed (explicit AND: FTS5 rejects implicit AND between two
/// parenthesised groups); variants of one term are ORed.
String _searchExpr(String normed) {
  final groups = <String>[];
  for (final t in normed.split(' ')) {
    if (t.isEmpty) continue;
    final variants = <String>{t};
    if (t.startsWith('ال') && t.length > 4) {
      variants.add(t.substring(2));
    } else {
      variants.add('ال$t');
    }
    groups.add('(${variants.map((v) => '"$v"*').join(' OR ')})');
  }
  return groups.join(' AND ');
}

class Book {
  final String id, name, short, author;
  final int count;
  const Book(this.id, this.name, this.short, this.author, this.count);
}

class Chapter {
  final int id;
  final String title;
  const Chapter(this.id, this.title);
}

class Hadith {
  final int id, num;
  final String book, bookName, short, text, chapter;
  final String? grades, expl, explSrc;
  const Hadith(this.id, this.num, this.book, this.bookName, this.short, this.text, this.chapter,
      this.grades, this.expl, this.explSrc);
}

const _cols =
    "h.id AS id, h.book AS book, h.num AS num, h.text AS text, b.name AS bname, b.short AS bshort, COALESCE(c.title, '') AS ctitle, h.grades AS grades, h.expl AS expl, h.expl_src AS esrc";
const _join = 'JOIN books b ON b.id=h.book LEFT JOIN chapters c ON c.id=h.chapter_id';

Hadith _h(Row r) => Hadith(r['id'] as int, r['num'] as int, r['book'] as String,
    r['bname'] as String, r['bshort'] as String, r['text'] as String, r['ctitle'] as String,
    r['grades'] as String?, r['expl'] as String?, r['esrc'] as String?);

List<Hadith> _searchSync(String p, String q) {
  final db = sqlite3.open(p, mode: OpenMode.readOnly);
  try {
    final n = normalizeAr(q);
    if (n.isEmpty) return [];
    ResultSet rs;
    if (RegExp(r'^[0-9]+$').hasMatch(n)) {
      rs = db.select('SELECT $_cols FROM hadiths h $_join WHERE h.num=? ORDER BY h.id LIMIT 40',
          [int.parse(n)]);
    } else {
      final expr = _searchExpr(n);
      rs = db.select(
          'SELECT $_cols FROM hadiths_fts JOIN hadiths h ON h.id=hadiths_fts.rowid $_join '
          'WHERE hadiths_fts MATCH ? ORDER BY rank LIMIT 50',
          [expr]);
    }
    return rs.map(_h).toList();
  } finally {
    db.dispose();
  }
}

Future<String> _sha(String p) async => (await sha256.bind(File(p).openRead()).first).toString();

String _quick(String p) {
  final db = sqlite3.open(p, mode: OpenMode.readOnly);
  try {
    return db.select('PRAGMA quick_check').first.values.first.toString();
  } finally {
    db.dispose();
  }
}

final _stop = {
  'في','من','ما','هو','هي','هل','عن','على','الى','إلى','ان','أن','انه','هذا','هذه','ذلك','كيف','لماذا',
  'متى','اين','أين','ماذا','الذي','التي','كان','يكون','حديث','احاديث','أحاديث','الحديث','الاحاديث',
  'الأحاديث','المتعلقة','المتعلقه','بشأن','حول','معنى','فوائد','الفرق','بين','و','او','أو','لي','هناك',
  'ورد','وردت','عنه','بها','به','له','لها',
  'اريد','اعطني','ابحث','ارني','اظهر','اعرض','هات','احضر','اذكر','اورد'
}.map(normalizeAr).toSet();

/// Topic words of a question: normalized words minus stopwords
/// (question/request words such as «أريد أحاديث عن» are removed).
List<String> _topicWords(String q) =>
    normalizeAr(q).split(' ').where((t) => t.length > 1 && !_stop.contains(t)).toList();

/// Topic synonyms: the same topic under a different chapter name
/// (e.g. Bukhari's book of fasting is titled «الصوم» while users ask for «الصيام»).
const _synonyms = {
  'الصيام': ['الصوم'],
  'الصوم': ['الصيام'],
};

List<Hadith> _askSync(String p, String q) {
  final words = _topicWords(q);
  if (words.isEmpty) return [];
  final topics = {...words};
  for (final w in words) {
    final s = _synonyms[w];
    if (s != null) topics.addAll(s);
  }
  final variants = <String>{};
  for (final t in topics) {
    variants.add(t);
    if (t.startsWith('ال') && t.length > 4) {
      variants.add(t.substring(2));
    } else {
      variants.add('ال$t');
    }
  }
  final expr = variants.map((t) => '"$t"*').join(' OR ');
  final db = sqlite3.open(p, mode: OpenMode.readOnly);
  try {
    final out = <Hadith>[];
    final seen = <int>{};
    // 1) Topical chapters: a hadith whose chapter title contains the topic
    // (e.g. «الصلاة» -> chapters «الصلاة»، «مواقيت الصلاة») is about the topic
    // even when the hadith text itself does not contain the word.
    final matched = <int>{};
    for (final c in db.select('SELECT id, title FROM chapters')) {
      final t = normalizeAr(c['title'] as String);
      for (final w in topics) {
        final bare = w.startsWith('ال') && w.length > 2 ? w.substring(2) : w;
        if (t.contains(w) || t.contains(bare)) {
          matched.add(c['id'] as int);
          break;
        }
      }
    }
    if (matched.isNotEmpty) {
      final ph = List.filled(matched.length, '?').join(',');
      final crs = db.select(
          'SELECT $_cols FROM hadiths h $_join '
          'WHERE h.chapter_id IN ($ph) ORDER BY b.sort, h.num LIMIT 3',
          matched.toList());
      for (final r in crs) {
        final h = _h(r);
        if (seen.add(h.id)) out.add(h);
      }
    }
    // 2) Full-text search fills the rest, best match first.
    final rs = db.select(
        'SELECT $_cols FROM hadiths_fts JOIN hadiths h ON h.id=hadiths_fts.rowid $_join '
        'WHERE hadiths_fts MATCH ? ORDER BY bm25(hadiths_fts, 1.0, 3.0) LIMIT 12',
        [expr]);
    for (final r in rs) {
      if (out.length >= 6) break;
      final h = _h(r);
      if (seen.add(h.id)) out.add(h);
    }
    return out;
  } finally {
    db.dispose();
  }
}

class Repo {
  Repo._();
  static final Repo i = Repo._();
  Database? _db;
  Database get db => _db!;

  Future<String> path() async {
    final d = await getApplicationSupportDirectory();
    return '${d.path}${Platform.pathSeparator}sunnah.db';
  }

  Future<bool> isInstalled() async {
    final f = File(await path());
    if (!f.existsSync() || f.lengthSync() < 100000) return false;
    try {
      final t = sqlite3.open(f.path, mode: OpenMode.readOnly);
      final n = t.select('SELECT COUNT(*) AS c FROM hadiths').first['c'] as int;
      t.dispose();
      return n > 0;
    } catch (_) {
      return false;
    }
  }

  /// Copies the bundled library to local storage (atomic: temp file + rename).
  Future<void> install(void Function(double) onProgress) async {
    final data = await rootBundle.load('assets/sunnah.db');
    final p = await path();
    final tmp = File('$p.tmp');
    final sink = tmp.openWrite();
    final total = data.lengthInBytes;
    const chunk = 1 << 20;
    for (var o = 0; o < total; o += chunk) {
      final e = min(o + chunk, total);
      sink.add(data.buffer.asUint8List(data.offsetInBytes + o, e - o));
      await sink.flush();
      onProgress(e / total);
    }
    await sink.close();
    final expected = (await rootBundle.loadString('assets/sunnah.db.sha256')).trim();
    final tp = tmp.path;
    final got = await Isolate.run(() => _sha(tp));
    if (got != expected) {
      tmp.deleteSync();
      throw Exception('فشل التحقق من سلامة ملف المكتبة (SHA-256)');
    }
    await tmp.rename(p);
    if (!await isInstalled()) {
      File(p).deleteSync();
      throw Exception('ملف المكتبة تالف');
    }
    (await SharedPreferences.getInstance()).setString('lib_sha', expected);
  }

  /// true إذا كانت المكتبة المدمجة في هذا الإصدار تختلف عن المثبتة.
  Future<bool> needsUpdate() async {
    final expected = (await rootBundle.loadString('assets/sunnah.db.sha256')).trim();
    return (await SharedPreferences.getInstance()).getString('lib_sha') != expected;
  }

  /// يقارن بصمة SHA-256 للمكتبة المثبتة مع البصمة المدمجة في التطبيق.
  Future<bool> verifyHash() async {
    final p = await path();
    final expected = (await rootBundle.loadString('assets/sunnah.db.sha256')).trim();
    return await Isolate.run(() => _sha(p)) == expected;
  }

  Future<String> quickCheck() async {
    final p = await path();
    return Isolate.run(() => _quick(p));
  }

  Future<int> sizeBytes() async => File(await path()).lengthSync();

  Future<List<Hadith>> ask(String q) async {
    final p = await path();
    return Isolate.run(() => _askSync(p, q));
  }

  /// Topic words detected in a question (for the assistant's reply).
  static List<String> topic(String q) => _topicWords(q);

  Future<void> open() async {
    _db ??= sqlite3.open(await path(), mode: OpenMode.readOnly);
  }

  List<Book> books() => db
      .select('SELECT id,name,short,author,cnt FROM books ORDER BY sort')
      .map((r) => Book(r['id'] as String, r['name'] as String, r['short'] as String,
          r['author'] as String, r['cnt'] as int))
      .toList();

  List<Chapter> chapters(String book) => db
      .select('SELECT id,title FROM chapters WHERE book=? ORDER BY num', [book])
      .map((r) => Chapter(r['id'] as int, r['title'] as String))
      .toList();

  List<Hadith> page(String where, Object arg, int limit, int offset) => db
      .select('SELECT $_cols FROM hadiths h $_join WHERE $where ORDER BY h.id LIMIT ? OFFSET ?',
          [arg, limit, offset])
      .map(_h)
      .toList();

  Hadith? byId(int id) {
    final rs = db.select('SELECT $_cols FROM hadiths h $_join WHERE h.id=?', [id]);
    return rs.isEmpty ? null : _h(rs.first);
  }

  List<Hadith> byIds(List<int> ids) {
    if (ids.isEmpty) return [];
    final rs = db.select(
        'SELECT $_cols FROM hadiths h $_join WHERE h.id IN (${List.filled(ids.length, '?').join(',')})',
        ids);
    final m = {for (final r in rs) r['id'] as int: _h(r)};
    return [for (final i in ids) if (m[i] != null) m[i]!];
  }

  int? neighbor(Hadith h, int delta) {
    final rs = db.select('SELECT id FROM hadiths WHERE id=? AND book=?', [h.id + delta, h.book]);
    return rs.isEmpty ? null : rs.first['id'] as int;
  }

  Hadith? daily() {
    const cond = 'length(text) BETWEEN 40 AND 400';
    final cnt = db.select('SELECT COUNT(*) AS c FROM hadiths WHERE $cond').first['c'] as int;
    if (cnt == 0) return null;
    final now = DateTime.now();
    final day = now.difference(DateTime(now.year, 1, 1)).inDays + now.year * 7;
    final rs = db.select(
        'SELECT $_cols FROM hadiths h $_join WHERE h.id = '
        '(SELECT id FROM hadiths WHERE $cond ORDER BY id LIMIT 1 OFFSET ?)',
        [(day * 97) % cnt]);
    return rs.isEmpty ? null : _h(rs.first);
  }

  Map<String, String> meta() =>
      {for (final r in db.select('SELECT key,value FROM meta')) r['key'] as String: r['value'] as String};

  Future<List<Hadith>> search(String q) async {
    final p = await path();
    return Isolate.run(() => _searchSync(p, q));
  }
}
