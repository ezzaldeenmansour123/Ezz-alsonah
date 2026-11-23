"""خادم اختياري للمساعد الذكي في تطبيق عز السنة.

تشغيل:  ANTHROPIC_API_KEY=... SERVER_TOKEN=... python3 server.py
SERVER_TOKEN إلزامي: رمز طويل عشوائي (مثال: openssl rand -hex 32) يطابق ما
تدخله في إعدادات التطبيق. بدونه لن يعمل الخادم — لأن خادماً بلا رمز يسمح لأي
شخص يعرف عنوانه باستخدام مفتاح Anthropic الخاص بك.
يجب وضعه خلف HTTPS (مثلاً عبر Caddy أو Cloudflare Tunnel) ثم إدخال عنوانه في إعدادات التطبيق.
المفتاح يبقى على الخادم ولا يدخل التطبيق.
"""
import json, os, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

KEY = os.environ['ANTHROPIC_API_KEY']
MODEL = os.environ.get('MODEL', 'claude-sonnet-5-5')
TOKEN = os.environ.get('SERVER_TOKEN')
if not TOKEN:
    raise SystemExit('SERVER_TOKEN is required: set a long random token, e.g. openssl rand -hex 32')

SYSTEM = (
    "أنت مساعد علمي داخل تطبيق للحديث النبوي. أجب بالعربية الفصيحة المبسطة اعتماداً حصراً على النصوص "
    "المرفقة برقم كل نص، واذكر أرقام المراجع مثل [1]. لا تُصدر فتاوى ولا أحكاماً شرعية مستقلة، ولا تنسب "
    "قولاً لعالم أو كتاب إلا إذا ورد في النصوص المرفقة. إن لم تكفِ النصوص للإجابة فقل ذلك صراحة. "
    "فرّق بين ما يقوله النص وما هو توضيح منك، وابدأ التوضيح بعبارة «توضيح مبسّط:»."
)


class H(BaseHTTPRequestHandler):
    def _send(self, code, obj):
        b = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_POST(self):
        if TOKEN and self.headers.get('Authorization') != f'Bearer {TOKEN}':
            return self._send(401, {'error': 'unauthorized'})
        try:
            d = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))))
            ctx = '\n\n'.join(
                f"[{p['n']}] {p['source']}\n{p['text']}"
                + (f"\nالشرح المنقول ({p.get('expl_src', '')}): {p['expl']}" if p.get('expl') else '')
                for p in d['passages'])
            body = json.dumps({
                'model': MODEL, 'max_tokens': 1000, 'system': SYSTEM,
                'messages': [{'role': 'user', 'content': f"السؤال: {d['question']}\n\nالنصوص:\n{ctx}"}],
            }).encode()
            req = urllib.request.Request('https://api.anthropic.com/v1/messages', body, {
                'x-api-key': KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json'})
            with urllib.request.urlopen(req, timeout=60) as r:
                out = json.loads(r.read())
            self._send(200, {'answer': ''.join(b.get('text', '') for b in out['content'] if b['type'] == 'text')})
        except Exception as e:
            self._send(502, {'error': str(e)})


if __name__ == '__main__':
    ThreadingHTTPServer(('0.0.0.0', int(os.environ.get('PORT', 8080))), H).serve_forever()
