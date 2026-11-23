import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'db.dart';

// ───────── الألوان الرسمية ─────────
const cream = Color(0xFFFFF9F4);
const pink = Color(0xFFF8DDE3);
const sky = Color(0xFFDCEFFA);
const blue = Color(0xFF79B5D8);
const rose = Color(0xFFD995A8);
const ink = Color(0xFF263746);

// ───────── الإعدادات والمفضلة (محلية) ─────────
class AppSettings extends ChangeNotifier {
  ThemeMode mode = ThemeMode.system;
  double fontSize = 24;
  bool amiri = true;
  String aiUrl = '', aiToken = '';
  bool aiConsent = false;
  late SharedPreferences p;
  Future<void> load() async {
    p = await SharedPreferences.getInstance();
    mode = ThemeMode.values[p.getInt('mode') ?? 0];
    fontSize = p.getDouble('font') ?? 24;
    amiri = p.getBool('amiri') ?? true;
    aiUrl = p.getString('ai_url') ?? '';
    aiToken = p.getString('ai_token') ?? '';
    aiConsent = p.getBool('ai_consent') ?? false;
  }

  void setAmiri(bool v) {
    amiri = v;
    p.setBool('amiri', v);
    notifyListeners();
  }

  void setAi(String url, String token) {
    aiUrl = url.trim();
    aiToken = token.trim();
    p.setString('ai_url', aiUrl);
    p.setString('ai_token', aiToken);
    notifyListeners();
  }

  void setConsent() {
    aiConsent = true;
    p.setBool('ai_consent', true);
  }

  void setMode(ThemeMode m) {
    mode = m;
    p.setInt('mode', m.index);
    notifyListeners();
  }

  void setFont(double v) {
    fontSize = v;
    p.setDouble('font', v);
    notifyListeners();
  }
}

class UserData extends ChangeNotifier {
  late SharedPreferences p;
  List<int> ids = [];
  Map<int, String> tags = {}, notes = {};
  List<int> history = [];

  Map<int, String> _readMap(String k) {
    final m = jsonDecode(p.getString(k) ?? '{}') as Map<String, dynamic>;
    return {for (final e in m.entries) int.parse(e.key): e.value as String};
  }

  Future<void> load() async {
    p = await SharedPreferences.getInstance();
    ids = (p.getStringList('favs') ?? []).map(int.parse).toList();
    history = (p.getStringList('history') ?? []).map(int.parse).toList();
    tags = _readMap('tags');
    notes = _readMap('notes');
  }

  void _save() {
    p.setStringList('favs', ids.map((e) => '$e').toList());
    p.setStringList('history', history.map((e) => '$e').toList());
    p.setString('tags', jsonEncode({for (final e in tags.entries) '${e.key}': e.value}));
    p.setString('notes', jsonEncode({for (final e in notes.entries) '${e.key}': e.value}));
    notifyListeners();
  }

  bool has(int id) => ids.contains(id);
  void toggle(int id) {
    if (has(id)) {
      ids.remove(id);
      tags.remove(id);
    } else {
      ids.add(id);
    }
    _save();
  }

  void setTag(int id, String t) {
    t.trim().isEmpty ? tags.remove(id) : tags[id] = t.trim();
    _save();
  }

  void setNote(int id, String t) {
    t.trim().isEmpty ? notes.remove(id) : notes[id] = t.trim();
    _save();
  }

  /// آخر موضع قراءة + سجل القراءة (آخر 100 حديث)
  void touch(int id) {
    history.remove(id);
    history.insert(0, id);
    if (history.length > 100) history.removeRange(100, history.length);
    _save();
  }

  void clearHistory() {
    history.clear();
    _save();
  }

  Set<String> get allTags => tags.values.toSet();
}

final settings = AppSettings();
final user = UserData();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await settings.load();
  await user.load();
  runApp(const SunnahApp());
}

ThemeData buildTheme(bool dark) {
  final scheme = dark
      ? const ColorScheme.dark(
          primary: blue, secondary: rose, surface: Color(0xFF1F2B35), onSurface: Color(0xFFEAF1F6))
      : const ColorScheme.light(
          primary: blue, secondary: rose, surface: Colors.white, onSurface: ink);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xFF141C23) : cream,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      foregroundColor: scheme.onSurface,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: scheme.onSurface),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF1B252E) : Colors.white,
      indicatorColor: dark ? const Color(0xFF33424F) : pink,
    ),
  );
}

class SunnahApp extends StatelessWidget {
  const SunnahApp({super.key});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (_, __) => MaterialApp(
        title: 'عز السنة',
        debugShowCheckedModeBanner: false,
        themeMode: settings.mode,
        theme: buildTheme(false),
        darkTheme: buildTheme(true),
        builder: (c, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const BootPage(),
      ),
    );
  }
}

// ───────── عناصر مشتركة ─────────
Widget softCard(BuildContext c,
    {required Widget child,
    VoidCallback? onTap,
    EdgeInsets padding = const EdgeInsets.all(16),
    Gradient? gradient}) {
  final dark = Theme.of(c).brightness == Brightness.dark;
  final r = BorderRadius.circular(20);
  return Container(
    decoration: BoxDecoration(
      color: dark ? const Color(0xFF1F2B35) : Colors.white,
      gradient: gradient,
      borderRadius: r,
      boxShadow: [
        BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.25 : 0.05), blurRadius: 12, offset: const Offset(0, 4))
      ],
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: r,
      child: InkWell(borderRadius: r, onTap: onTap, child: Padding(padding: padding, child: child)),
    ),
  );
}

Widget fadeIn(BuildContext c, Widget child) {
  if (MediaQuery.of(c).disableAnimations) return child;
  return TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 350),
    builder: (_, v, ch) => Opacity(opacity: v, child: ch),
    child: child,
  );
}

TextStyle hadithStyle(double size, {double h = 1.9, FontWeight w = FontWeight.w600}) =>
    TextStyle(fontSize: size, height: h, fontWeight: w, fontFamily: settings.amiri ? 'Amiri' : null);

Future<String?> askText(BuildContext c, String title, String initial,
    {int lines = 1, List<String> chips = const []}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: ctl, maxLines: lines, autofocus: true),
        if (chips.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(spacing: 6, children: [
              for (final t in chips) ActionChip(label: Text(t), onPressed: () => ctl.text = t),
            ]),
          ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('حفظ')),
      ],
    ),
  );
}

String gradeAr(String g) {
  const m = {
    'sahih': 'صحيح',
    'hasan': 'حسن',
    "da'if": 'ضعيف',
    'daif': 'ضعيف',
    'hasan sahih': 'حسن صحيح',
    'sahih lighairihi': 'صحيح لغيره',
    'hasan lighairihi': 'حسن لغيره',
    'mawdu': 'موضوع',
  };
  return m[g.toLowerCase().trim()] ?? g;
}

Widget passageCard(BuildContext c, Hadith h) => softCard(
      c,
      onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => ReaderPage(h.id))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (h.expl != null) ...[
          const Text('شرح منقول', style: TextStyle(fontSize: 12, color: blue, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(h.expl!, maxLines: 5, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, height: 1.8)),
          const SizedBox(height: 6),
          Text('المصدر: ${h.explSrc ?? ''}', style: const TextStyle(fontSize: 11)),
          const Divider(height: 16),
        ] else
          const Text('نص حديثي', style: TextStyle(fontSize: 12, color: blue, fontWeight: FontWeight.w700)),
        Text(h.text, maxLines: 3, overflow: TextOverflow.ellipsis, style: hadithStyle(15, h: 1.8, w: FontWeight.w400)),
        const SizedBox(height: 6),
        Text('${h.bookName} • حديث ${h.num}', style: const TextStyle(fontSize: 12, color: rose)),
      ]),
    );

Widget hadithCard(BuildContext c, Hadith h) => softCard(
      c,
      onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => ReaderPage(h.id))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(h.text, maxLines: 3, overflow: TextOverflow.ellipsis, style: hadithStyle(16, h: 1.8, w: FontWeight.w400)),
        const SizedBox(height: 8),
        Text('${h.bookName} • حديث ${h.num}', style: const TextStyle(fontSize: 12, color: rose)),
      ]),
    );

Widget emptyState(IconData icon, String text, {String? button, VoidCallback? onTap}) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(radius: 48, backgroundColor: pink, child: Icon(icon, size: 48, color: rose)),
          const SizedBox(height: 20),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, height: 1.7)),
          if (button != null) ...[
            const SizedBox(height: 20),
            FilledButton.tonal(onPressed: onTap, child: Text(button)),
          ],
        ]),
      ),
    );

class LogoMark extends StatelessWidget {
  final double size;
  const LogoMark(this.size, {super.key});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size * 0.9), painter: _LogoPainter());
}

class _LogoPainter extends CustomPainter {
  Path _poly(List<List<double>> pts, bool mirror) {
    final p = Path();
    for (var i = 0; i < pts.length; i++) {
      final x = mirror ? 100 - pts[i][0] : pts[i][0];
      i == 0 ? p.moveTo(x, pts[i][1]) : p.lineTo(x, pts[i][1]);
    }
    return p..close();
  }

  @override
  void paint(Canvas c, Size s) {
    c.scale(s.width / 100);
    const outer = [[50.0, 84.0], [8.0, 72.0], [6.0, 46.0], [50.0, 60.0]];
    const inner = [[50.0, 72.0], [16.0, 62.0], [14.0, 50.0], [50.0, 62.0]];
    const gem = [[50.0, 8.0], [62.0, 24.0], [50.0, 40.0], [38.0, 24.0]];
    final a = Paint()..color = blue;
    final b = Paint()..color = const Color(0xFFB7D9EE);
    for (final m in [false, true]) {
      c.drawPath(_poly(outer, m), a);
      c.drawPath(_poly(inner, m), b);
    }
    c.drawPath(_poly(gem, false), Paint()..color = rose);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ───────── شاشة البداية وتجهيز المكتبة ─────────
class BootPage extends StatefulWidget {
  const BootPage({super.key});
  @override
  State<BootPage> createState() => _BootPageState();
}

class _BootPageState extends State<BootPage> {
  double? progress;
  bool installing = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => error = null);
    try {
      final repo = Repo.i;
      if (!await repo.isInstalled() || await repo.needsUpdate()) {
        setState(() => installing = true);
        await repo.install((p) {
          if (mounted) setState(() => progress = p);
        });
      }
      await repo.open();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        pageBuilder: (_, __, ___) => const Shell(),
        transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
      ));
    } catch (e) {
      if (mounted) setState(() => error = 'تعذّر تجهيز المكتبة:\n$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark ? [const Color(0xFF141C23), const Color(0xFF1F2B35)] : [cream, pink, sky],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const LogoMark(130),
              const SizedBox(height: 16),
              const Text('عز السنة',
                  style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800, color: blue)),
              const SizedBox(height: 8),
              Text('افهم هدي النبي ﷺ، واعمل به',
                  style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 40),
              if (error != null) ...[
                Text(error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: _start, child: const Text('إعادة المحاولة')),
              ] else ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(value: installing ? progress : null, minHeight: 6),
                ),
                const SizedBox(height: 12),
                Text(installing
                    ? 'جارٍ تجهيز المكتبة… ${((progress ?? 0) * 100).round()}٪ (مرة واحدة فقط)'
                    : 'جارٍ التحميل…'),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

// ───────── الهيكل والتنقل ─────────
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  void go(int i) => setState(() => tab = i);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: tab, children: [
        HomePage(onTab: go),
        const BooksPage(),
        FavsPage(onTab: go),
        const SearchPage(),
        const SettingsPage(showBack: false),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: go,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.menu_book_rounded), label: 'الكتب'),
          NavigationDestination(icon: Icon(Icons.star_rounded), label: 'المفضلة'),
          NavigationDestination(icon: Icon(Icons.search_rounded), label: 'البحث'),
          NavigationDestination(icon: Icon(Icons.more_horiz_rounded), label: 'المزيد'),
        ],
      ),
    );
  }
}

// ───────── الرئيسية ─────────
class HomePage extends StatefulWidget {
  final void Function(int) onTab;
  const HomePage({super.key, required this.onTab});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final Hadith? daily = Repo.i.daily();
  late final List<Book> books = Repo.i.books();

  Widget _tile(IconData icon, String label, VoidCallback onTap) =>
        softCard(context,
            onTap: onTap,
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
            child: Column(children: [
              Icon(icon, color: blue, size: 30),
              const SizedBox(height: 8),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
            ]));

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          IconButton(onPressed: () => widget.onTab(3), icon: const Icon(Icons.search_rounded, color: blue)),
          const Expanded(
              child: Center(
                  child: Text('عز السنة',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: blue)))),
          IconButton(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const SettingsPage(showBack: true))),
              icon: const Icon(Icons.settings_rounded, color: blue)),
        ]),
        const SizedBox(height: 8),
        if (daily != null)
          fadeIn(
            context,
            softCard(
              context,
              padding: const EdgeInsets.all(20),
              gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: dark ? [const Color(0xFF3A2A31), const Color(0xFF22384A)] : [pink, sky]),
              child: Column(children: [
                const Text('حديث اليوم', style: TextStyle(fontSize: 13, color: rose)),
                const SizedBox(height: 10),
                Text(daily!.text,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: hadithStyle(19)),
                const SizedBox(height: 10),
                Text('${daily!.bookName} • حديث ${daily!.num}', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => ReaderPage(daily!.id))),
                  child: const Text('اقرأ الحديث كاملاً'),
                ),
              ]),
            ),
          ),
        const ContinueCard(),
        const SizedBox(height: 20),
        Row(children: [
          const Icon(Icons.menu_book_rounded, color: blue, size: 20),
          const SizedBox(width: 6),
          const Text('كتب السنة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const Spacer(),
          TextButton(onPressed: () => widget.onTab(1), child: const Text('عرض الكل')),
        ]),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.05,
          children: [
            for (final b in books.take(6))
              softCard(context,
                  padding: const EdgeInsets.all(8),
                  onTap: () =>
                      Navigator.push(context, MaterialPageRoute(builder: (_) => BookPage(b))),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.auto_stories_rounded, color: rose, size: 30),
                    const SizedBox(height: 6),
                    Text(b.short, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
                  ])),
          ],
        ),
        const SizedBox(height: 20),
        const Row(children: [
          Icon(Icons.star_rounded, color: blue, size: 20),
          SizedBox(width: 6),
          Text('مميزات التطبيق', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.05,
          children: [
            _tile(Icons.search_rounded, 'بحث متقدم', () => widget.onTab(3)),
            _tile(Icons.psychology_alt_rounded, 'المساعد العلمي',
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AssistantPage()))),
            _tile(Icons.bookmark_rounded, 'المفضلة', () => widget.onTab(2)),
            _tile(Icons.history_rounded, 'سجل القراءة',
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryPage()))),
            _tile(Icons.storage_rounded, 'المكتبة',
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LibraryPage()))),
          ],
        ),
      ]),
    );
  }
}

// ───────── الكتب ─────────
class BooksPage extends StatefulWidget {
  const BooksPage({super.key});
  @override
  State<BooksPage> createState() => _BooksPageState();
}

class _BooksPageState extends State<BooksPage> {
  late final List<Book> books = Repo.i.books();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('كتب السنة')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: books.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (c, i) {
          final b = books[i];
          return softCard(c,
              onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => BookPage(b))),
              child: Row(children: [
                Container(
                  width: 48,
                  height: 56,
                  decoration: BoxDecoration(
                      color: i.isEven ? sky : pink, borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.auto_stories_rounded, color: i.isEven ? blue : rose),
                ),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(b.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('${b.count} حديث', style: const TextStyle(fontSize: 13, color: rose)),
                  Text(b.author, style: const TextStyle(fontSize: 12)),
                ])),
                const Icon(Icons.chevron_left_rounded),
              ]));
        },
      ),
    );
  }
}

class BookPage extends StatefulWidget {
  final Book book;
  const BookPage(this.book, {super.key});
  @override
  State<BookPage> createState() => _BookPageState();
}

class _BookPageState extends State<BookPage> {
  late final List<Chapter> chapters = Repo.i.chapters(widget.book.id);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.book.name)),
      body: chapters.isEmpty
          ? PagedHadiths(where: 'h.book=?', arg: widget.book.id)
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: chapters.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (c, i) => softCard(c,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  onTap: () => Navigator.push(
                      c,
                      MaterialPageRoute(
                          builder: (_) => Scaffold(
                                appBar: AppBar(
                                    title: Text(chapters[i].title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 16))),
                                body: PagedHadiths(where: 'h.chapter_id=?', arg: chapters[i].id),
                              ))),
                  child: Row(children: [
                    Expanded(
                        child: Text(chapters[i].title.isEmpty ? 'باب ${i + 1}' : chapters[i].title,
                            maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15))),
                    const Icon(Icons.chevron_left_rounded),
                  ])),
            ),
    );
  }
}

class PagedHadiths extends StatefulWidget {
  final String where;
  final Object arg;
  const PagedHadiths({super.key, required this.where, required this.arg});
  @override
  State<PagedHadiths> createState() => _PagedHadithsState();
}

class _PagedHadithsState extends State<PagedHadiths> {
  final items = <Hadith>[];
  final sc = ScrollController();
  bool more = true;

  void _fetch() {
    if (!more) return;
    final r = Repo.i.page(widget.where, widget.arg, 30, items.length);
    items.addAll(r);
    if (r.length < 30) more = false;
  }

  @override
  void initState() {
    super.initState();
    _fetch();
    sc.addListener(() {
      if (sc.position.pixels > sc.position.maxScrollExtent - 500 && more) setState(_fetch);
    });
  }

  @override
  void dispose() {
    sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return emptyState(Icons.menu_book_rounded, 'لا توجد أحاديث في هذا القسم');
    return ListView.separated(
      controller: sc,
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (c, i) => hadithCard(c, items[i]),
    );
  }
}

// ───────── قارئ الحديث ─────────
class ReaderPage extends StatefulWidget {
  final int id;
  const ReaderPage(this.id, {super.key});
  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  Hadith? h;

  @override
  void initState() {
    super.initState();
    h = Repo.i.byId(widget.id);
    if (h != null) WidgetsBinding.instance.addPostFrameCallback((_) => user.touch(h!.id));
  }

  void _go(int d) {
    final id = h == null ? null : Repo.i.neighbor(h!, d);
    if (id == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('لا يوجد حديث آخر في هذا الاتجاه')));
      return;
    }
    setState(() => h = Repo.i.byId(id));
    user.touch(id);
  }

  String _shareText() => '${h!.text}\n\n— ${h!.bookName}، حديث رقم ${h!.num}';

  Widget _action(IconData icon, String label, VoidCallback onTap) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: rose),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ),
      );

  void _fontSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => AnimatedBuilder(
        animation: settings,
        builder: (_, __) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('حجم الخط', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Slider(min: 16, max: 40, value: settings.fontSize, onChanged: settings.setFont),
          ]),
        ),
      ),
    );
  }

  Future<void> _tagDialog() async {
    final t = await askText(context, 'تصنيف الحديث', user.tags[h!.id] ?? '', chips: user.allTags.toList());
    if (t != null) user.setTag(h!.id, t);
  }

  Future<void> _noteDialog() async {
    final t = await askText(context, 'ملاحظتي على الحديث', user.notes[h!.id] ?? '', lines: 4);
    if (t != null) user.setNote(h!.id, t);
  }

  Widget _gradesCard(BuildContext c, Hadith x) {
    var items = <dynamic>[];
    try {
      items = x.grades == null ? [] : jsonDecode(x.grades!) as List<dynamic>;
    } catch (_) {}
    return softCard(c,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('درجة الحديث', style: TextStyle(fontSize: 13, color: rose, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (items.isEmpty)
            const Text('لم يرد حكم على هذا الحديث في المصدر.', style: TextStyle(fontSize: 14))
          else
            for (final g in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                    '${gradeAr('${g['grade']}')}${('${g['grader']}').isEmpty ? '' : ' — ${g['grader']}'}',
                    style: const TextStyle(fontSize: 14)),
              ),
          const SizedBox(height: 4),
          const Text('الأحكام منقولة بأسماء أصحابها كما وردت في المصدر، ولا يصدرها التطبيق.',
              style: TextStyle(fontSize: 11)),
        ]));
  }

  Widget _explCard(BuildContext c, Hadith x) {
    return softCard(c,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('الشرح', style: TextStyle(fontSize: 13, color: rose, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (x.expl != null) ...[
            SelectableText(x.expl!, style: const TextStyle(fontSize: 16, height: 1.9)),
            const SizedBox(height: 8),
            Text('المصدر: ${x.explSrc ?? ''}\nنص منقول كما هو وليس مولّداً بالذكاء الاصطناعي.',
                style: const TextStyle(fontSize: 11, height: 1.6)),
          ] else
            const Text('لا يتوفر شرح موثق لهذا الحديث في المكتبة الحالية.', style: TextStyle(fontSize: 14)),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => Navigator.push(
                  c, MaterialPageRoute(builder: (_) => AssistantPage(about: x))),
              icon: const Icon(Icons.psychology_alt_rounded, size: 18),
              label: const Text('اسأل المساعد عن هذا الحديث'),
            ),
          ),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final x = h;
    return Scaffold(
      appBar: AppBar(title: Text(x?.bookName ?? '')),
      body: x == null
          ? emptyState(Icons.error_outline, 'الحديث غير موجود')
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: AnimatedBuilder(
                key: ValueKey(x.id),
                animation: Listenable.merge([settings, user]),
                builder: (c, _) => ListView(padding: const EdgeInsets.all(20), children: [
                  if (x.chapter.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                          color: rose.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(24)),
                      child: Text(x.chapter, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
                    ),
                  const SizedBox(height: 20),
                  SelectableText(x.text, style: hadithStyle(settings.fontSize, h: 2.0)),
                  const SizedBox(height: 16),
                  Center(
                      child: Text('${x.bookName} — حديث رقم ${x.num}',
                          style: const TextStyle(fontSize: 14, color: rose))),
                  if (user.tags[x.id] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Center(child: Chip(label: Text(user.tags[x.id]!), avatar: const Icon(Icons.label_rounded, size: 16))),
                    ),
                  const Divider(height: 32),
                  _gradesCard(c, x),
                  const SizedBox(height: 12),
                  _explCard(c, x),
                  if (user.notes[x.id] != null) ...[
                    const SizedBox(height: 12),
                    softCard(c,
                        onTap: _noteDialog,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('ملاحظتي', style: TextStyle(fontSize: 13, color: rose, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text(user.notes[x.id]!, style: const TextStyle(fontSize: 15, height: 1.8)),
                        ])),
                  ],
                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    TextButton.icon(
                        onPressed: () => _go(-1),
                        icon: const Icon(Icons.chevron_right_rounded),
                        label: const Text('السابق')),
                    TextButton.icon(
                        onPressed: () => _go(1),
                        icon: const Icon(Icons.chevron_left_rounded),
                        label: const Text('التالي'),
                        iconAlignment: IconAlignment.end),
                  ]),
                ]),
              ),
            ),
      bottomNavigationBar: x == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: softCard(
                  context,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(children: [
                    AnimatedBuilder(
                      animation: user,
                      builder: (_, __) => _action(
                          user.has(x.id) ? Icons.star_rounded : Icons.star_border_rounded,
                          user.has(x.id) ? 'في المفضلة' : 'للمفضلة', () {
                        final adding = !user.has(x.id);
                        user.toggle(x.id);
                        if (adding) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: const Text('أُضيف إلى المفضلة'),
                              action: SnackBarAction(label: 'تصنيف', onPressed: _tagDialog)));
                        }
                      }),
                    ),
                    _action(Icons.copy_rounded, 'نسخ', () {
                      Clipboard.setData(ClipboardData(text: _shareText()));
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('تم نسخ الحديث')));
                    }),
                    _action(Icons.share_rounded, 'مشاركة', () => Share.share(_shareText())),
                    _action(Icons.edit_note_rounded, 'ملاحظة', _noteDialog),
                    _action(Icons.text_fields_rounded, 'الخط', _fontSheet),
                  ]),
                ),
              ),
            ),
    );
  }
}

class ContinueCard extends StatelessWidget {
  const ContinueCard({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: user,
        builder: (c, _) {
          if (user.history.isEmpty) return const SizedBox.shrink();
          final h = Repo.i.byId(user.history.first);
          if (h == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: softCard(c,
                onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => ReaderPage(h.id))),
                child: Row(children: [
                  const Icon(Icons.bookmark_added_rounded, color: rose),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('تابع القراءة', style: TextStyle(fontWeight: FontWeight.w700)),
                    Text('${h.bookName} • حديث ${h.num}', style: const TextStyle(fontSize: 13)),
                  ])),
                  const Icon(Icons.chevron_left_rounded),
                ])),
          );
        },
      );
}

// ───────── البحث ─────────
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final ctrl = TextEditingController();
  final cache = <String, List<Hadith>>{};
  List<Hadith>? res;
  Timer? t;

  void _changed(String v) {
    t?.cancel();
    t = Timer(const Duration(milliseconds: 300), () async {
      final q = v.trim();
      if (q.isEmpty) {
        setState(() => res = null);
        return;
      }
      final r = cache[q] ?? await Repo.i.search(q);
      cache[q] = r;
      if (!mounted || ctrl.text.trim() != q) return;
      setState(() => res = r);
    });
  }

  @override
  void dispose() {
    t?.cancel();
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('البحث')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: ctrl,
            onChanged: _changed,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'ابحث في الكتب …',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    ctrl.clear();
                    setState(() => res = null);
                  }),
              filled: true,
              fillColor: dark ? const Color(0xFF1F2B35) : pink.withValues(alpha: 0.6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: res == null
              ? emptyState(Icons.search_rounded,
                  'اكتب كلمات من الحديث أو رقمه.\nيعمل البحث دون تشكيل ودون إنترنت.')
              : res!.isEmpty
                  ? emptyState(Icons.search_off_rounded, 'لا توجد نتائج مطابقة')
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: res!.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (c, i) => i == 0
                          ? Text('نتائج البحث (${res!.length})',
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))
                          : hadithCard(c, res![i - 1]),
                    ),
        ),
      ]),
    );
  }
}

// ───────── المفضلة ─────────
class FavsPage extends StatefulWidget {
  final void Function(int) onTab;
  const FavsPage({super.key, required this.onTab});
  @override
  State<FavsPage> createState() => _FavsPageState();
}

class _FavsPageState extends State<FavsPage> {
  String q = '';
  String? tag;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المفضلة')),
      body: AnimatedBuilder(
        animation: user,
        builder: (c, _) {
          if (user.ids.isEmpty) {
            return emptyState(Icons.bookmark_rounded, 'لا توجد أحاديث مضافة\nإلى المفضلة بعد',
                button: 'تصفح الكتب', onTap: () => widget.onTab(1));
          }
          final nq = normalizeAr(q);
          var all = Repo.i.byIds(user.ids.reversed.toList());
          if (tag != null) all = all.where((h) => user.tags[h.id] == tag).toList();
          final list = nq.isEmpty
              ? all
              : all
                  .where((h) =>
                      normalizeAr(h.text).contains(nq) || normalizeAr(user.notes[h.id] ?? '').contains(nq))
                  .toList();
          final tags = user.allTags.toList();
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (c, i) => i == 0
                ? Column(children: [
                    TextField(
                        onChanged: (v) => setState(() => q = v),
                        decoration: InputDecoration(
                          hintText: 'ابحث في المفضلة …',
                          prefixIcon: const Icon(Icons.search_rounded),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        )),
                    if (tags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Wrap(spacing: 8, children: [
                          ChoiceChip(label: const Text('الكل'), selected: tag == null, onSelected: (_) => setState(() => tag = null)),
                          for (final t in tags)
                            ChoiceChip(label: Text(t), selected: tag == t, onSelected: (_) => setState(() => tag = t)),
                        ]),
                      ),
                  ])
                : hadithCard(c, list[i - 1]),
          );
        },
      ),
    );
  }
}

// ───────── سجل القراءة ─────────
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سجل القراءة'), actions: [
        IconButton(
            tooltip: 'مسح السجل',
            onPressed: () => user.clearHistory(),
            icon: const Icon(Icons.delete_outline_rounded)),
      ]),
      body: AnimatedBuilder(
        animation: user,
        builder: (c, _) {
          if (user.history.isEmpty) return emptyState(Icons.history_rounded, 'لم تقرأ أي حديث بعد');
          final list = Repo.i.byIds(user.history);
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (c, i) => hadithCard(c, list[i]),
          );
        },
      ),
    );
  }
}

// ───────── المساعد العلمي ─────────
class _Msg {
  final int kind; // 0 سؤال، 1 نتائج المكتبة، 2 توضيح ذكاء اصطناعي، 3 معلومة
  final String text;
  final List<Hadith> items;
  _Msg(this.kind, this.text, [this.items = const []]);
}

class AssistantPage extends StatefulWidget {
  final Hadith? about;
  const AssistantPage({super.key, this.about});
  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final ctl = TextEditingController();
  final sc = ScrollController();
  final msgs = <_Msg>[];
  bool busy = false;

  @override
  void initState() {
    super.initState();
    msgs.add(_Msg(
        3,
        'أنا المساعد العلمي. أبحث في نصوص المكتبة وشروحها المنقولة وأعرض لك المصادر. '
        'لا أصدر فتاوى ولا أنسب قولاً لأحد دون مصدر.\nجرّب: «ما الأحاديث المتعلقة بالصبر؟»'));
    if (widget.about != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _send('ما معنى هذا الحديث وما فوائده؟', about: widget.about));
    }
  }

  @override
  void dispose() {
    ctl.dispose();
    sc.dispose();
    super.dispose();
  }

  void _scroll() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (sc.hasClients) sc.animateTo(sc.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  Future<String> _callBackend(String q, List<Hadith> ps) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await c.postUrl(Uri.parse(settings.aiUrl));
      req.headers.contentType = ContentType.json;
      if (settings.aiToken.isNotEmpty) req.headers.set('Authorization', 'Bearer ${settings.aiToken}');
      req.add(utf8.encode(jsonEncode({
        'question': q,
        'passages': [
          for (var i = 0; i < ps.length; i++)
            {
              'n': i + 1,
              'source': '${ps[i].bookName}، حديث رقم ${ps[i].num}',
              'text': ps[i].text.length > 1500 ? ps[i].text.substring(0, 1500) : ps[i].text,
              if (ps[i].expl != null) 'expl': ps[i].expl,
              if (ps[i].explSrc != null) 'expl_src': ps[i].explSrc,
            }
        ],
      })));
      final res = await req.close().timeout(const Duration(seconds: 60));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) throw Exception('رمز الاستجابة ${res.statusCode}');
      return (jsonDecode(body) as Map<String, dynamic>)['answer'] as String;
    } finally {
      c.close();
    }
  }

  Future<void> _send(String q, {Hadith? about}) async {
    q = q.trim();
    if (q.isEmpty || busy) return;
    ctl.clear();
    setState(() {
      msgs.add(_Msg(0, q));
      busy = true;
    });
    _scroll();
    var found = <Hadith>[];
    try {
      found = about != null ? [about] : await Repo.i.ask(q);
    } catch (_) {}
    if (!mounted) return;
    if (about == null) {
      final topic = Repo.topic(q);
      setState(() => msgs.add(found.isEmpty
          ? _Msg(3, 'لا تتوفر لدي معلومات كافية في المكتبة للإجابة عن هذا السؤال. جرّب كلمات أخرى.')
          : _Msg(
              1,
              topic.isEmpty
                  ? 'هذه أقرب النصوص في المكتبة لسؤالك (مرتبة حسب الصلة):'
                  : 'وجدت ${found.length} أحاديث عن «${topic.join(' ')}» (مرتبة حسب الصلة):',
              found)));
    }
    if (found.isNotEmpty && settings.aiUrl.isNotEmpty) {
      if (!settings.aiConsent) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('إرسال إلى خادم الذكاء الاصطناعي'),
            content: Text('سيُرسل سؤالك والنصوص المسترجعة من المكتبة إلى الخادم الذي أدخلت عنوانه:\n${settings.aiUrl}\n\nهل توافق؟'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('أوافق')),
            ],
          ),
        );
        if (ok != true) {
          setState(() {
            msgs.add(_Msg(3, 'لم يُرسل شيء إلى الخادم.'));
            busy = false;
          });
          return;
        }
        settings.setConsent();
      }
      try {
        final ans = await _callBackend(q, found);
        if (mounted) setState(() => msgs.add(_Msg(2, ans, found)));
      } catch (e) {
        if (mounted) setState(() => msgs.add(_Msg(3, 'تعذّر الاتصال بخادم الذكاء الاصطناعي: $e')));
      }
    } else if (about != null) {
      setState(() => msgs.add(_Msg(
          3,
          found.first.expl != null
              ? 'الشرح المنقول لهذا الحديث معروض في صفحة الحديث. لتوليد توضيح مبسّط بالذكاء الاصطناعي أدخل عنوان الخادم في الإعدادات.'
              : 'لا يتوفر شرح موثق لهذا الحديث في المكتبة. لتوليد توضيح مبسّط بالذكاء الاصطناعي أدخل عنوان الخادم في الإعدادات.')));
    }
    if (mounted) setState(() => busy = false);
    _scroll();
  }

  Widget _bubble(BuildContext c, _Msg m) {
    switch (m.kind) {
      case 0:
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(c).size.width * 0.8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: blue.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(16)),
            child: Text(m.text),
          ),
        );
      case 1:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m.text, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          for (final h in m.items) Padding(padding: const EdgeInsets.only(bottom: 8), child: passageCard(c, h)),
        ]);
      case 2:
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: rose.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('توضيح مولّد بالذكاء الاصطناعي — ليس فتوى ولا شرحاً منقولاً عن عالم',
                style: TextStyle(fontSize: 12, color: rose, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SelectableText(m.text, style: const TextStyle(height: 1.9)),
            const Divider(height: 20),
            for (var i = 0; i < m.items.length; i++)
              Text('[${i + 1}] ${m.items[i].bookName} — حديث ${m.items[i].num}', style: const TextStyle(fontSize: 12)),
          ]),
        );
      default:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: sky.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(16)),
          child: Text(m.text, style: const TextStyle(height: 1.7, color: ink)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المساعد العلمي')),
      body: Column(children: [
        Expanded(
          child: ListView.separated(
            controller: sc,
            padding: const EdgeInsets.all(16),
            itemCount: msgs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (c, i) => _bubble(c, msgs[i]),
          ),
        ),
        if (busy) const LinearProgressIndicator(minHeight: 2),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: ctl,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _send,
                  decoration: InputDecoration(
                    hintText: 'اكتب سؤالك …',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ),
              ),
              IconButton.filled(onPressed: busy ? null : () => _send(ctl.text), icon: const Icon(Icons.send_rounded)),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ───────── المكتبة (التنزيلات والتحديثات) ─────────
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final meta = Repo.i.meta();
  final books = Repo.i.books();
  String? result;
  bool checking = false;
  int size = 0;

  @override
  void initState() {
    super.initState();
    Repo.i.sizeBytes().then((v) {
      if (mounted) setState(() => size = v);
    });
  }

  Future<void> _check() async {
    setState(() {
      checking = true;
      result = null;
    });
    String r;
    try {
      final q = await Repo.i.quickCheck();
      final h = await Repo.i.verifyHash();
      r = (q == 'ok' && h)
          ? 'المكتبة سليمة ✔ (فحص قاعدة البيانات وبصمة SHA-256 متطابقان)'
          : 'تحذير: نتيجة الفحص "$q" — البصمة ${h ? 'متطابقة' : 'غير متطابقة'}. أعد تثبيت التطبيق.';
    } catch (e) {
      r = 'تعذّر الفحص: $e';
    }
    if (mounted) {
      setState(() {
        checking = false;
        result = r;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المكتبة')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        softCard(context,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('عدد الأحاديث: ${meta['total'] ?? '—'}'),
              Text('الحجم على الجهاز: ${(size / 1048576).toStringAsFixed(1)} ميغابايت'),
              Text('تاريخ بناء المكتبة: ${meta['built'] ?? '—'}'),
              Text('المصدر: ${meta['source'] ?? '—'}'),
              Text('إصدار المصدر: ${meta['source_commit'] ?? '—'}'),
            ])),
        const SizedBox(height: 12),
        for (final b in books)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: softCard(context,
                child: Row(children: [
                  const Icon(Icons.check_circle_rounded, color: blue),
                  const SizedBox(width: 12),
                  Expanded(child: Text(b.name)),
                  Text('${b.count} حديث', style: const TextStyle(fontSize: 12, color: rose)),
                ])),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: checking ? null : _check,
          icon: const Icon(Icons.verified_user_rounded),
          label: Text(checking ? 'جارٍ الفحص…' : 'التحقق من سلامة البيانات'),
        ),
        if (result != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(result!)),
        const SizedBox(height: 16),
        const Text(
            'تحديث المكتبة: المكتبة مدمجة في التطبيق، وتتحدث تلقائياً عند تثبيت إصدار أحدث منه. '
            'مفضلتك وملاحظاتك وسجلك محفوظة بشكل منفصل ولا تتأثر بالتحديث.',
            style: TextStyle(fontSize: 12, height: 1.7)),
      ]),
    );
  }
}

// ───────── الإعدادات ─────────
class SettingsPage extends StatefulWidget {
  final bool showBack;
  const SettingsPage({super.key, required this.showBack});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final urlCtl = TextEditingController(text: settings.aiUrl);
  late final tokCtl = TextEditingController(text: settings.aiToken);

  @override
  void dispose() {
    urlCtl.dispose();
    tokCtl.dispose();
    super.dispose();
  }

  void _info(String title, String body) => showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(body, style: const TextStyle(height: 1.8))),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
        ),
      );

  Widget _h(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: rose)),
      );

  Widget _row(IconData i, String t, VoidCallback f) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: softCard(context, onTap: f, child: Row(children: [
          Icon(i, color: blue),
          const SizedBox(width: 12),
          Expanded(child: Text(t)),
          const Icon(Icons.chevron_left_rounded),
        ])),
      );

  void _saveAi() {
    final u = urlCtl.text.trim();
    if (u.isNotEmpty && !u.startsWith('https://')) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('يجب أن يبدأ العنوان بـ https://')));
      return;
    }
    settings.setAi(u, tokCtl.text);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(u.isEmpty ? 'تم تعطيل الذكاء الاصطناعي' : 'تم حفظ إعدادات الخادم')));
  }

  @override
  Widget build(BuildContext context) {
    final meta = Repo.i.meta();
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات'), automaticallyImplyLeading: widget.showBack),
      body: AnimatedBuilder(
        animation: settings,
        builder: (c, _) => ListView(padding: const EdgeInsets.all(16), children: [
          _h('المظهر'),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.light, label: Text('فاتح')),
              ButtonSegment(value: ThemeMode.dark, label: Text('داكن')),
              ButtonSegment(value: ThemeMode.system, label: Text('تلقائي')),
            ],
            selected: {settings.mode},
            onSelectionChanged: (s) => settings.setMode(s.first),
          ),
          _h('الخط'),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('أميري')),
              ButtonSegment(value: false, label: Text('خط النظام')),
            ],
            selected: {settings.amiri},
            onSelectionChanged: (s) => settings.setAmiri(s.first),
          ),
          const SizedBox(height: 10),
          softCard(c,
              child: Column(children: [
                Text('بسم الله الرحمن الرحيم', style: hadithStyle(settings.fontSize, h: 1.8)),
                Slider(min: 16, max: 40, value: settings.fontSize, onChanged: settings.setFont),
              ])),
          _h('المكتبة'),
          _row(Icons.storage_rounded, 'المكتبة والتحقق من سلامة البيانات (${meta['total'] ?? '—'} حديث)',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LibraryPage()))),
          _h('المساعد الذكي (اختياري)'),
          softCard(c,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text(
                    'المساعد يعمل محلياً دون إنترنت. لتفعيل «التوضيح المولّد بالذكاء الاصطناعي» أدخل عنوان خادمك الخاص '
                    '(مثال جاهز في مجلد backend). لا تُخزَّن أي مفاتيح داخل التطبيق.',
                    style: TextStyle(fontSize: 12, height: 1.7)),
                const SizedBox(height: 10),
                TextField(
                    controller: urlCtl,
                    keyboardType: TextInputType.url,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(labelText: 'عنوان الخادم https://…', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(
                    controller: tokCtl,
                    obscureText: true,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(labelText: 'رمز الوصول (اختياري)', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                FilledButton(onPressed: _saveAi, child: const Text('حفظ')),
              ])),
          _h('عن التطبيق'),
          _row(Icons.lock_outline_rounded, 'الخصوصية',
              () => _info('الخصوصية',
                  'لا يجمع التطبيق أي بيانات. المفضلة والملاحظات وسجل القراءة والإعدادات محفوظة على جهازك فقط.\n\n'
                  'لا يستخدم التطبيق الإنترنت إلا إذا أدخلت أنت عنوان خادم الذكاء الاصطناعي؛ عندها يُرسل سؤالك '
                  'والنصوص المسترجعة إلى ذلك الخادم فقط، وبعد موافقتك.')),
          _row(Icons.info_outline_rounded, 'حول التطبيق والمصادر',
              () => _info(
                  'عز السنة',
                  'الإصدار 1.0.0\n\n'
                  'النصوص: المتن العربي للأحاديث (ملكية عامة) والدرجات بأسماء المحدّثين، من مجموعة بيانات '
                  'QuranLab على Hugging Face (${meta['source_commit'] ?? '—'}) المبنية على مشروعي fawazahmed0/hadith-api '
                  'وmhashim6/Open-Hadith-Data.\n'
                  'الشروح: من موسوعة HadeethEnc.com (IslamHouse) بنصها دون تعديل مع ذكر المصدر.\n'
                  'الخط: أميري (رخصة OFL).\n\n'
                  'الشرح المنقول متوفر فقط لأحاديث الموسوعة. بقية الأحاديث يُعلَن فيها بوضوح أن الشرح غير متوفر.\n'
                  'لا يصدر التطبيق فتاوى، والتوضيح بالذكاء الاصطناعي يظهر دائماً موسوماً ومنفصلاً عن النص والشرح.\n\n'
                  'غير مضمّن: الإشعارات، والتلاوة الصوتية.')),
        ]),
      ),
    );
  }
}
