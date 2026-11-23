#!/usr/bin/env python3
"""Builds assets/sunnah.db (SQLite + FTS5) from a snapshot of the HF dataset quranlab/hadith.

usage: build_db.py <snapshot-dir> <out.db> [revision]
Arabic matn only (public domain), per-hadith grades with grader names, and
HadeethEnc explanations (open-with-attribution). Nothing is generated or invented.

Chapter (kitab) titles: the dataset only carries a numeric book_number, so the
Arabic kitab names below are the canonical book titles of each collection,
cross-checked against fawazahmed0/hadith-api section numbering and hadith-number
ranges (the QuranLab book_number groups match those ranges exactly, except for
book_number 0 — see below). If a number has no title here, the builder falls
back to "الكتاب رقم N" and prints a warning instead of inventing a name.

book_number 0: in this dataset it is NOT a real book for Bukhari and Muslim —
it holds hadiths the source left unclassified (scattered across the whole
numbering range, verified 2026-11-23), so they are labelled "أحاديث غير مصنفة".
For Ibn Majah, book 0 IS a real book (hadiths 1-266, contiguous): كتاب السنة.
"""
import datetime, glob, hashlib, json, os, re, sqlite3, sys

# collection id in the dataset -> (arabic name, short, author)
BOOKS = [
    ('bukhari', 'صحيح البخاري', 'البخاري', 'الإمام محمد بن إسماعيل البخاري'),
    ('muslim', 'صحيح مسلم', 'مسلم', 'الإمام مسلم بن الحجاج النيسابوري'),
    ('abudawud', 'سنن أبي داود', 'أبو داود', 'الإمام أبو داود السجستاني'),
    ('tirmidhi', 'جامع الترمذي', 'الترمذي', 'الإمام أبو عيسى الترمذي'),
    ('nasai', 'سنن النسائي', 'النسائي', 'الإمام أحمد بن شعيب النسائي'),
    ('ibnmajah', 'سنن ابن ماجه', 'ابن ماجه', 'الإمام ابن ماجه القزويني'),
    ('malik', 'موطأ مالك', 'مالك', 'الإمام مالك بن أنس'),
    ('nawawi', 'الأربعون النووية', 'النووي', 'الإمام يحيى بن شرف النووي'),
    ('hadeethenc', 'موسوعة الأحاديث النبوية (مع الشرح)', 'الموسوعة', 'IslamHouse / وزارة الشؤون الإسلامية السعودية'),
]
EXPL_SRC = 'HadeethEnc.com — موسوعة الأحاديث النبوية المترجمة (IslamHouse)'

# Canonical Arabic kitab titles, keyed by the dataset's book_number.
BOOK_TITLES = {
    'bukhari': {
        0: 'أحاديث غير مصنفة',
        1: 'بدء الوحي', 2: 'الإيمان', 3: 'العلم', 4: 'الوضوء', 5: 'الغسل',
        6: 'الحيض', 7: 'التيمم', 8: 'الصلاة', 9: 'مواقيت الصلاة', 10: 'الأذان',
        11: 'الجمعة', 12: 'صلاة الخوف', 13: 'العيدين', 14: 'الوتر', 15: 'الاستسقاء',
        16: 'الكسوف', 17: 'سجود القرآن', 18: 'تقصير الصلاة', 19: 'التهجد',
        20: 'فضل الصلاة في مسجد مكة والمدينة', 21: 'العمل في الصلاة', 22: 'السهو',
        23: 'الجنائز', 24: 'الزكاة', 25: 'الحج', 26: 'العمرة', 27: 'المحصر',
        28: 'جزاء الصيد', 29: 'فضائل المدينة', 30: 'الصوم', 31: 'صلاة التراويح',
        32: 'فضل ليلة القدر', 33: 'الاعتكاف', 34: 'البيوع', 35: 'السلم',
        36: 'الشفعة', 37: 'الإجارة', 38: 'الحوالات', 39: 'الكفالة', 40: 'الوكالة',
        41: 'المزارعة', 42: 'المساقاة', 43: 'الاستقراض وأداء الديون والحجر والتفليس',
        44: 'الخصومات', 45: 'اللقطة', 46: 'المظالم والغصب', 47: 'الشركة',
        48: 'الرهن', 49: 'العتق', 50: 'المكاتب', 51: 'الهبة وفضلها والتحريض عليها',
        52: 'الشهادات', 53: 'الصلح', 54: 'الشروط', 55: 'الوصايا', 56: 'الجهاد والسير',
        57: 'فرض الخمس', 58: 'الجزية والموادعة', 59: 'بدء الخلق', 60: 'الأنبياء',
        61: 'المناقب', 62: 'فضائل أصحاب النبي ﷺ', 63: 'مناقب الأنصار', 64: 'المغازي',
        65: 'تفسير القرآن', 66: 'فضائل القرآن', 67: 'النكاح', 68: 'الطلاق',
        69: 'النفقات', 70: 'الأطعمة', 71: 'العقيقة', 72: 'الذبائح والصيد',
        73: 'الأضاحي', 74: 'الأشربة', 75: 'المرضى', 76: 'الطب', 77: 'اللباس',
        78: 'الأدب', 79: 'الاستئذان', 80: 'الدعوات', 81: 'الرقاق', 82: 'القدر',
        83: 'الأيمان والنذور', 84: 'الكفارات', 85: 'الفرائض', 86: 'الحدود',
        87: 'الديات', 88: 'استتابة المرتدين والمعاندين وقتالهم', 89: 'الإكراه',
        90: 'الحيل', 91: 'التعبير', 92: 'الفتن', 93: 'الأحكام', 94: 'التمني',
        95: 'أخبار الآحاد', 96: 'الاعتصام بالكتاب والسنة', 97: 'التوحيد',
    },
    'muslim': {
        0: 'أحاديث غير مصنفة',
        1: 'الإيمان', 2: 'الطهارة', 3: 'الحيض', 4: 'الصلاة',
        5: 'المساجد ومواضع الصلاة', 6: 'صلاة المسافرين وقصرها', 7: 'الجمعة',
        8: 'صلاة العيدين', 9: 'صلاة الاستسقاء', 10: 'صلاة الكسوف', 11: 'الجنائز',
        12: 'الزكاة', 13: 'الصيام', 14: 'الاعتكاف', 15: 'الحج', 16: 'النكاح',
        17: 'الرضاع', 18: 'الطلاق', 19: 'اللعان', 20: 'العتق', 21: 'البيوع',
        22: 'المساقاة', 23: 'الفرائض', 24: 'الهبات', 25: 'الوصية', 26: 'النذر',
        27: 'الأيمان', 28: 'القسامة والمحاربين والقصاص والديات', 29: 'الحدود',
        30: 'الأقضية', 31: 'اللقطة', 32: 'الجهاد والسير', 33: 'الإمارة',
        34: 'الصيد والذبائح وما يؤكل من الحيوان', 35: 'الأضاحي', 36: 'الأشربة',
        37: 'اللباس والزينة', 38: 'الآداب', 39: 'السلام', 40: 'الألفاظ من الأدب وغيرها',
        41: 'الشعر', 42: 'الرؤيا', 43: 'الفضائل', 44: 'فضائل الصحابة',
        45: 'البر والصلة والآداب', 46: 'القدر', 47: 'العلم',
        48: 'الذكر والدعاء والتوبة والاستغفار', 49: 'الرقاق', 50: 'التوبة',
        51: 'صفات المنافقين وأحكامهم', 52: 'صفة القيامة والجنة والنار',
        53: 'صفة الجنة وصفة نعيمها وأهلها', 54: 'الفتن وأشراط الساعة',
        55: 'الزهد والرقائق', 56: 'التفسير',
    },
    'abudawud': {
        1: 'الطهارة', 2: 'الصلاة', 3: 'الاستسقاء', 4: 'صلاة السفر', 5: 'التطوع',
        6: 'صلاة شهر رمضان', 7: 'سجود القرآن', 8: 'الوتر', 9: 'الزكاة',
        10: 'اللقطة', 11: 'المناسك والحج', 12: 'النكاح', 13: 'الطلاق',
        14: 'الصيام', 15: 'الجهاد', 16: 'الضحايا', 17: 'الصيد', 18: 'الوصايا',
        19: 'الفرائض', 20: 'الخراج والفيء والإمارة', 21: 'الجنائز',
        22: 'الأيمان والنذور', 23: 'البيوع', 24: 'الإجارة', 25: 'الأقضية',
        26: 'العلم', 27: 'الأشربة', 28: 'الأطعمة', 29: 'الطب',
        30: 'الكهانة والتطير', 31: 'العتق', 32: 'الحروف والقراءات', 33: 'الحمام',
        34: 'اللباس', 35: 'الترجل', 36: 'الخاتم', 37: 'الفتن والملاحم',
        38: 'المهدي', 39: 'الملاحم', 40: 'الحدود', 41: 'الديات', 42: 'السنة',
        43: 'الأدب',
    },
    'tirmidhi': {
        1: 'الطهارة', 2: 'الصلاة', 3: 'الوتر', 4: 'الجمعة', 5: 'العيدين',
        6: 'السفر', 7: 'الزكاة', 8: 'الصوم', 9: 'الحج', 10: 'الجنائز',
        11: 'النكاح', 12: 'الرضاع', 13: 'الطلاق واللعان', 14: 'البيوع',
        15: 'الأحكام', 16: 'الديات', 17: 'الحدود', 18: 'الصيد', 19: 'الأضاحي',
        20: 'النذور والأيمان', 21: 'السير', 22: 'فضائل الجهاد', 23: 'الجهاد',
        24: 'اللباس', 25: 'الأطعمة', 26: 'الأشربة', 27: 'البر والصلة',
        28: 'الطب', 29: 'الفرائض', 30: 'الوصايا', 31: 'الولاء والهبة',
        32: 'القدر', 33: 'الفتن', 34: 'الرؤيا', 35: 'الشهادات', 36: 'الزهد',
        37: 'صفة القيامة والرقاق والورع', 38: 'صفة الجنة', 39: 'صفة جهنم',
        40: 'الإيمان', 41: 'العلم', 42: 'الاستئذان', 43: 'الآداب', 44: 'الأمثال',
        45: 'فضائل القرآن', 46: 'القراءات', 47: 'تفسير القرآن', 48: 'الدعوات',
        49: 'المناقب',
    },
    'nasai': {
        1: 'الطهارة', 2: 'المياه', 3: 'الحيض والاستحاضة', 4: 'الغسل والتيمم',
        5: 'الصلاة', 6: 'المواقيت', 7: 'الأذان', 8: 'المساجد', 9: 'القبلة',
        10: 'الإمامة', 11: 'افتتاح الصلاة', 12: 'التطبيق', 13: 'السهو',
        14: 'الجمعة', 15: 'قصر الصلاة في السفر', 16: 'الكسوف', 17: 'الاستسقاء',
        18: 'صلاة الخوف', 19: 'صلاة العيدين', 20: 'قيام الليل وتطوع النهار',
        21: 'الجنائز', 22: 'الصيام', 23: 'الزكاة', 24: 'الحج', 25: 'الجهاد',
        26: 'النكاح', 27: 'الطلاق', 28: 'الخيل والسبق والرمي', 29: 'الوقف',
        30: 'الوصايا', 31: 'النحل', 32: 'الهبة', 33: 'الرقبى', 34: 'العمرى',
        35: 'المزارعة', 36: 'عشرة النساء', 37: 'تحريم الدم', 38: 'قسمة الفيء',
        39: 'البيعة', 40: 'العقيقة', 41: 'الفرع والعتيرة', 42: 'الصيد والذبائح',
        43: 'الأضاحي', 44: 'البيوع', 45: 'القسامة والقصاص والديات',
        46: 'قطع السارق', 47: 'الإيمان وشرائعه', 48: 'الزينة', 49: 'آداب القضاة',
        50: 'الاستعاذة', 51: 'الأشربة',
    },
    'ibnmajah': {
        0: 'كتاب السنة',
        1: 'الطهارة وسننها', 2: 'الصلاة', 3: 'الأذان والسنة فيها',
        4: 'المساجد والجماعات', 5: 'إقامة الصلاة والسنة فيها', 6: 'الجنائز',
        7: 'الصيام', 8: 'الزكاة', 9: 'النكاح', 10: 'الطلاق', 11: 'الكفارات',
        12: 'التجارات', 13: 'الأحكام', 14: 'الهبات', 15: 'الصدقات', 16: 'الرهون',
        17: 'الشفعة', 18: 'اللقطة', 19: 'العتق', 20: 'الحدود', 21: 'الديات',
        22: 'الوصايا', 23: 'الفرائض', 24: 'الجهاد', 25: 'المناسك', 26: 'الأضاحي',
        27: 'الذبائح', 28: 'الصيد', 29: 'الأطعمة', 30: 'الأشربة', 31: 'الطب',
        32: 'اللباس', 33: 'الأدب', 34: 'الدعاء', 35: 'تعبير الرؤيا', 36: 'الفتن',
        37: 'الزهد',
    },
    'malik': {
        1: 'وقوت الصلاة', 2: 'الطهارة', 3: 'الصلاة', 4: 'السهو', 5: 'الجمعة',
        6: 'الصلاة في رمضان', 7: 'التهجد', 8: 'صلاة الجماعة',
        9: 'قصر الصلاة في السفر', 10: 'العيدين', 11: 'صلاة الخوف',
        12: 'صلاة الكسوف', 13: 'الاستسقاء', 14: 'القبلة', 15: 'القرآن',
        16: 'الجنائز', 17: 'الزكاة', 18: 'الصيام', 19: 'الاعتكاف', 20: 'الحج',
        21: 'الجهاد', 22: 'النذور والأيمان', 23: 'الضحايا', 24: 'الذبائح',
        25: 'الصيد', 26: 'العقيقة', 27: 'الفرائض', 28: 'النكاح', 29: 'الطلاق',
        30: 'الرضاع', 31: 'البيوع', 32: 'القراض', 33: 'المساقاة',
        34: 'كراء الأرض', 35: 'الشفعة', 36: 'الأقضية', 37: 'الوصية',
        38: 'العتق والولاء', 39: 'المكاتب', 40: 'المدبر', 41: 'الحدود',
        42: 'الأشربة', 43: 'الديات', 44: 'القسامة', 45: 'المدينة', 46: 'القدر',
        47: 'حسن الخلق', 48: 'اللباس', 49: 'صفة النبي ﷺ', 50: 'العين',
        51: 'الشعر', 52: 'الرؤيا', 53: 'السلام', 54: 'الجامع', 55: 'البيعة',
        56: 'الكلام', 57: 'جهنم', 58: 'الصدقة', 59: 'العلم', 60: 'دعوة المظلوم',
        61: 'أسماء النبي ﷺ',
    },
}

TASHKEEL = re.compile(r'[\u064B-\u065F\u0670\u06D6-\u06ED\u0640]')
ALEF = re.compile(r'[إأآٱ]')
NONWORD = re.compile(r'[^\u0621-\u064A\u0660-\u0669a-zA-Z0-9\s]')
SPACES = re.compile(r'\s+')


def norm(s):
    s = TASHKEEL.sub('', s)
    s = ALEF.sub('ا', s).replace('ى', 'ي').replace('ة', 'ه')
    s = NONWORD.sub(' ', s)
    return SPACES.sub(' ', s).strip()


def _strip_prefix(w):
    """Strip one leading Arabic prefix (و/ف/ب/ل/ك, alone or before ال) from a word.

    «بالنيات» -> «نيات»، «والصلاة» -> «صلاه»، «الصلاة» -> «صلاه».
    Guards keep real words intact: «الله» stays «الله» (remainder too short),
    «بالغ» stays «بالغ». Returns None when nothing sensible can be stripped.
    """
    for p in ('وال', 'فال', 'بال', 'لل', 'كال'):
        if w.startswith(p) and len(w) - len(p) >= 2:
            return w[len(p):]
    if w.startswith('ال') and len(w) - 2 >= 3:
        return w[2:]
    for p in ('و', 'ف', 'ب', 'ل', 'ك'):
        if w.startswith(p) and len(w) - 1 >= 2:
            return w[1:]
    return None


def search_norm(s):
    """Normalized text for the FTS index: the normalized words plus, for each
    word, its prefix-stripped form. This is what makes «النيات» find
    «بالنيات» (the index holds «نيات» alongside «بالنيات»), while the
    displayed text is never changed. The query side (lib/db.dart) adds the
    matching «ال» variants; the two meet in the middle."""
    words = norm(s).split(' ')
    out = []
    for w in words:
        if not w:
            continue
        out.append(w)
        stripped = _strip_prefix(w)
        if stripped and stripped != w:
            out.append(stripped)
    return ' '.join(out)


def s(x):
    """clean string from possibly-NaN/None cell"""
    if x is None:
        return ''
    if isinstance(x, float):
        return ''
    return str(x).strip()


def load_rows(dirpath):
    import pandas as pd
    files = sorted(glob.glob(os.path.join(dirpath, '*.parquet')))
    if not files:
        return None
    df = pd.concat([pd.read_parquet(f) for f in files], ignore_index=True)
    return df.to_dict('records')


def grades_json(row):
    g = row.get('grades')
    items = []
    try:
        for it in list(g) if g is not None and not isinstance(g, float) else []:
            gr, gd = s(it.get('grader')), s(it.get('grade'))
            if gd:
                items.append({'grader': gr, 'grade': gd})
    except Exception:
        items = []
    if not items and s(row.get('grade')):
        items.append({'grader': s(row.get('grader')) or 'HadeethEnc', 'grade': s(row.get('grade'))})
    return json.dumps(items, ensure_ascii=False) if items else None


def build(snapshot, out, rev):
    if os.path.exists(out):
        os.remove(out)
    con = sqlite3.connect(out)
    cur = con.cursor()
    cur.executescript('''
    CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
    CREATE TABLE books(id TEXT PRIMARY KEY, name TEXT, short TEXT, author TEXT, sort INTEGER, cnt INTEGER);
    CREATE TABLE chapters(id INTEGER PRIMARY KEY, book TEXT, num INTEGER, title TEXT);
    CREATE TABLE hadiths(id INTEGER PRIMARY KEY, book TEXT, num INTEGER, chapter_id INTEGER,
                         text TEXT, grades TEXT, expl TEXT, expl_src TEXT);
    CREATE VIRTUAL TABLE hadiths_fts USING fts5(norm, expl, tokenize='unicode61 remove_diacritics 0');
    ''')
    total = hid = cid = 0
    untitled = []
    for sort, (bid, name, short, author) in enumerate(BOOKS):
        rows = load_rows(os.path.join(snapshot, f'{bid}-ar'))
        if not rows:
            print(f'!! {bid}-ar: not found, skipped')
            continue
        if 'seq' in rows[0]:
            rows.sort(key=lambda r: r.get('seq') or 0)
        # sections from book_number, titled from BOOK_TITLES (no invented names:
        # a missing title falls back to the number and is reported below)
        sec_ids, sec_count = {}, 0
        nums = [r.get('book_number') for r in rows]
        distinct = sorted({int(n) for n in nums if n is not None and not isinstance(n, float)})
        if bid != 'hadeethenc' and len(distinct) > 1:
            for k in distinct:
                cid += 1
                sec_count += 1
                sec_ids[k] = cid
                title = BOOK_TITLES.get(bid, {}).get(k)
                if title is None:
                    title = f'الكتاب رقم {k}'
                    untitled.append(f'{bid}:{k}')
                cur.execute('INSERT INTO chapters VALUES(?,?,?,?)', (cid, bid, k, title))
        n = 0
        for i, r in enumerate(rows):
            t = s(r.get('text'))
            if not t:
                continue
            if bid == 'hadeethenc' and s(r.get('attribution_text')):
                t = t + '\n' + s(r.get('attribution_text'))
            hid += 1
            n += 1
            m = re.match(r'\d+', s(r.get('hadith_number')))
            num = int(m.group()) if m else n
            bn = r.get('book_number')
            ch = sec_ids.get(int(bn)) if bn is not None and not isinstance(bn, float) and sec_ids else None
            expl = s(r.get('explanation')) if bid == 'hadeethenc' else ''
            cur.execute('INSERT INTO hadiths VALUES(?,?,?,?,?,?,?,?)',
                        (hid, bid, num, ch, t, grades_json(r), expl or None, EXPL_SRC if expl else None))
            cur.execute('INSERT INTO hadiths_fts(rowid, norm, expl) VALUES(?,?,?)',
                        (hid, search_norm(t), search_norm(expl) if expl else ''))
        cur.execute('INSERT INTO books VALUES(?,?,?,?,?,?)', (bid, name, short, author, sort, n))
        print(f'{bid}: {n} hadiths, {sec_count} sections')
        total += n
    if total < 1000:
        print('ERROR: far too few hadiths; source layout probably changed.')
        sys.exit(1)
    if untitled:
        print(f'WARNING: {len(untitled)} sections without a title (fell back to numbers): {", ".join(untitled)}')
    cur.execute("INSERT INTO hadiths_fts(hadiths_fts) VALUES('optimize')")
    cur.executemany('INSERT INTO meta VALUES(?,?)', [
        ('source', 'huggingface.co/datasets/quranlab/hadith'),
        ('source_commit', rev),
        ('built', datetime.date.today().isoformat()),
        ('total', str(total)),
        ('titles', 'canonical Arabic kitab names, cross-checked against '
                   'fawazahmed0/hadith-api section numbering; book_number 0 = '
                   'unclassified for bukhari/muslim, كتاب السنة for ibnmajah'),
        ('credits', 'matn: fawazahmed0/hadith-api (public domain); grades: named muhaddith graders; '
                    'explanations: HadeethEnc.com (IslamHouse); packaging: QuranLab'),
    ])
    cur.execute('CREATE INDEX idx_h_book ON hadiths(book, num)')
    cur.execute('CREATE INDEX idx_h_chap ON hadiths(chapter_id)')
    cur.execute('CREATE INDEX idx_c_book ON chapters(book, num)')
    con.commit()
    con.execute('VACUUM')
    con.close()
    h = hashlib.sha256(open(out, 'rb').read()).hexdigest()
    open(out + '.sha256', 'w').write(h)
    print(f'OK total={total} size={os.path.getsize(out)/1e6:.1f}MB sha256={h[:12]}…')


if __name__ == '__main__':
    build(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else 'unknown')
