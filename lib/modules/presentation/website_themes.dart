/// Hand-built looks for themed note websites. The model only chooses one;
/// every page shares [_base] and layers a theme's variables and signature
/// rules on top. Fonts are system stacks, except the bundled Caveat and Lora
/// that the view embeds when a theme names them.
class WebsiteTheme {
  const WebsiteTheme({
    required this.id,
    required this.name,
    required this.swatch,
    required this.css,
    this.fonts = const [],
  });
  final String id, name;

  /// Background and accent colours for the picker, as 0xAARRGGBB.
  final (int, int) swatch;
  final String css;

  /// Bundled font families this theme uses, embedded at view time.
  final List<String> fonts;
}

/// Bundled fonts a theme may embed: family and asset path.
const websiteFontAssets = {
  'Caveat': 'assets/fonts/Caveat-Medium.ttf',
  'Lora': 'assets/fonts/Lora-Regular.ttf',
};

const _base = '''
*,*::before,*::after{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{margin:0;background:var(--bg);color:var(--ink);font:400 17px/1.65 var(--body);-webkit-font-smoothing:antialiased}
.page{max-width:720px;margin:0 auto;padding:0 20px 56px}
.hero{padding:56px 0 32px}
.kicker{margin:0 0 12px;font:600 12px/1.2 var(--body);letter-spacing:.14em;text-transform:uppercase;color:var(--accent)}
h1,h2,h3{font-family:var(--head);color:var(--ink);margin:0;font-weight:var(--head-weight,700);line-height:1.15;text-wrap:balance}
h1{font-size:clamp(34px,9vw,56px);letter-spacing:-.02em}
.tagline{margin:16px 0 0;font-size:19px;color:var(--muted);max-width:34em}
.s{margin:0 0 40px}
.s>h2{font-size:clamp(23px,5.5vw,30px);margin-bottom:14px}
.s p{margin:0 0 12px}
.cards{display:grid;gap:14px;grid-template-columns:repeat(auto-fit,minmax(210px,1fr))}
.card{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);padding:18px 18px 16px;box-shadow:var(--shadow)}
.card h3{font-size:18px;margin-bottom:6px}
.card p{margin:0;color:var(--muted)}
.list{list-style:none;margin:0;padding:0}
.list li{position:relative;padding:12px 0 12px 28px;border-bottom:1px solid var(--line)}
.list li::before{content:"";position:absolute;left:4px;top:22px;width:9px;height:9px;border-radius:50%;background:var(--accent)}
.list strong{font-weight:650}
.timeline{list-style:none;margin:0;padding:0 0 0 22px;border-left:2px solid var(--line)}
.timeline li{position:relative;padding:0 0 22px 6px}
.timeline li::before{content:"";position:absolute;left:-30px;top:6px;width:14px;height:14px;border-radius:50%;background:var(--bg);border:3px solid var(--accent)}
.when{display:block;font:600 13px/1.3 var(--body);letter-spacing:.06em;text-transform:uppercase;color:var(--accent);margin-bottom:4px}
.timeline p{margin:0}
blockquote{margin:0;padding:8px 0 8px 22px;border-left:4px solid var(--accent)}
blockquote p{font:italic 400 clamp(22px,5.5vw,28px)/1.4 var(--head);margin:0 0 10px}
cite{font-style:normal;color:var(--muted);font-size:15px}
.stats{display:grid;gap:12px;grid-template-columns:repeat(auto-fit,minmax(140px,1fr))}
.stat{background:var(--surface);border-radius:var(--radius);padding:18px;border:1px solid var(--line)}
.stat b{display:block;font:var(--head-weight,700) clamp(28px,7vw,38px)/1.1 var(--head);color:var(--accent);margin-bottom:4px}
.stat span{color:var(--muted);font-size:15px}
figure{margin:0 0 16px}
figure img{display:block;width:100%;height:auto;border-radius:var(--radius);background:var(--line)}
figcaption{margin-top:8px;font-size:14px;color:var(--muted)}
.gallery{display:grid;gap:10px;grid-template-columns:repeat(auto-fit,minmax(150px,1fr))}
.gallery figure{margin:0}
.end{margin-top:56px;padding-top:20px;border-top:1px solid var(--line);font-size:13px;color:var(--muted)}
''';

const _accents = '''
.a-ink{--accent:#3b3f5c}.a-rose{--accent:#c2255c}.a-ocean{--accent:#1864ab}
.a-forest{--accent:#2b8a3e}.a-sun{--accent:#d9480f}.a-plum{--accent:#862e9c}
''';

const websiteThemes = [
  WebsiteTheme(
    id: 'editorial',
    name: 'Editorial',
    swatch: (0xFFFBF8F3, 0xFF1F1D1A),
    fonts: ['Lora'],
    css: '''
body{--bg:#fbf8f3;--surface:#fff;--ink:#1f1d1a;--muted:#5f5a52;--line:#e6dfd3;--radius:4px;--shadow:none;--head:"Lora","Iowan Old Style","New York",Georgia,serif;--body:"Lora","Iowan Old Style",Georgia,serif;--head-weight:400}
.hero{text-align:center;border-bottom:1px solid var(--ink);margin-bottom:40px}
.hero .tagline{margin-left:auto;margin-right:auto;font-style:italic}
.s>h2{border-top:3px double var(--ink);padding-top:14px}
.s-text>p:first-of-type::first-letter{float:left;font:400 64px/.85 var(--head);padding:6px 8px 0 0;color:var(--accent)}
''',
  ),
  WebsiteTheme(
    id: 'zine',
    name: 'Zine',
    swatch: (0xFFFFF4D6, 0xFF111111),
    css: '''
body{--bg:#fff4d6;--surface:#fff;--ink:#111;--muted:#333;--line:#111;--radius:0;--shadow:5px 5px 0 #111;--head:"Avenir Next Condensed","Arial Narrow","Helvetica Neue",Impact,sans-serif;--body:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;--head-weight:800}
h1,h2{text-transform:uppercase;letter-spacing:-.01em}
h1{font-size:clamp(44px,13vw,80px);line-height:.95}
.hero{padding-top:40px}
.kicker{display:inline-block;background:var(--ink);color:var(--bg);padding:6px 10px}
.s>h2{display:inline-block;background:var(--accent);color:#fff;padding:4px 10px;transform:rotate(-1.5deg)}
.card,.stat{border:2px solid var(--ink)}
.card:nth-child(even){transform:rotate(.8deg)}.card:nth-child(odd){transform:rotate(-.6deg)}
.list li{border-bottom:2px dashed var(--ink)}
.list li::before{border-radius:0;transform:rotate(45deg)}
blockquote{border-left:8px solid var(--ink);background:var(--surface);padding:18px 20px;box-shadow:var(--shadow)}
figure img{border:2px solid var(--ink);box-shadow:var(--shadow)}
''',
  ),
  WebsiteTheme(
    id: 'garden',
    name: 'Garden',
    swatch: (0xFFF1F6EE, 0xFF2B8A3E),
    css: '''
body{--bg:#f1f6ee;--surface:#fff;--ink:#1e2b1f;--muted:#55665a;--line:#dbe7d4;--radius:22px;--shadow:0 10px 30px -18px rgba(30,60,30,.45);--head:ui-rounded,"SF Pro Rounded","Nunito","Varela Round",system-ui,sans-serif;--body:ui-rounded,"SF Pro Rounded",system-ui,-apple-system,sans-serif;--head-weight:700}
body{background:radial-gradient(circle at 100% 0,#dff0d8 0,transparent 45%),radial-gradient(circle at 0 30%,#fdf3dc 0,transparent 40%),var(--bg)}
.hero{text-align:center}
.hero .tagline{margin-left:auto;margin-right:auto}
.kicker{display:inline-block;background:var(--surface);padding:7px 14px;border-radius:99px;box-shadow:var(--shadow)}
.card,.stat{border:0}
.list li{background:var(--surface);border:0;border-radius:16px;margin-bottom:8px;padding-right:14px}
.list li::before{left:12px}
.list li{padding-left:34px}
blockquote{border:0;background:var(--surface);border-radius:var(--radius);padding:22px;box-shadow:var(--shadow)}
''',
  ),
  WebsiteTheme(
    id: 'notebook',
    name: 'Notebook',
    swatch: (0xFFFFFDF5, 0xFF1864AB),
    fonts: ['Caveat'],
    css: '''
body{--bg:#fffdf5;--surface:#fffef9;--ink:#26304a;--muted:#58607a;--line:#c9d6ea;--radius:3px;--shadow:0 1px 3px rgba(0,0,0,.12);--head:"Caveat","Bradley Hand","Segoe Print",cursive;--body:"Iowan Old Style",Georgia,serif;--head-weight:500}
body{background-image:linear-gradient(90deg,transparent 30px,#f3b8b8 30px,#f3b8b8 32px,transparent 32px),repeating-linear-gradient(transparent 0,transparent 27px,#dbe5f3 27px,#dbe5f3 28px);background-attachment:local}
.page{padding-left:48px}
h1{font-size:clamp(46px,12vw,72px);letter-spacing:0}
.s>h2{font-size:clamp(32px,8vw,40px)}
.card h3{font-size:26px}
.card{transform:rotate(-.6deg);background:#fff8c5;border:0;box-shadow:0 6px 14px -8px rgba(0,0,0,.35)}
.card:nth-child(even){transform:rotate(.7deg);background:#e3f2ff}
.stat b{font-size:44px}
blockquote p{font-size:clamp(28px,7vw,36px)}
figure img{border:8px solid #fff;box-shadow:0 6px 16px -6px rgba(0,0,0,.35);transform:rotate(-1deg)}
''',
  ),
  WebsiteTheme(
    id: 'night',
    name: 'Night',
    swatch: (0xFF0F1222, 0xFF9775FA),
    css: '''
body{--bg:#0f1222;--surface:#181c33;--ink:#eef0ff;--muted:#a3a8c7;--line:#2a2f4d;--radius:14px;--shadow:0 0 0 1px rgba(255,255,255,.04),0 18px 40px -20px #000;--head:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;--body:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;--head-weight:750}
body{background:radial-gradient(ellipse at 50% -20%,#2a2160 0,transparent 60%),var(--bg)}
.a-ink{--accent:#b4bcff}.a-rose{--accent:#f783ac}.a-ocean{--accent:#74c0fc}
.a-forest{--accent:#8ce99a}.a-sun{--accent:#ffc078}.a-plum{--accent:#da77f2}
h1{background:linear-gradient(120deg,var(--ink) 30%,var(--accent));-webkit-background-clip:text;background-clip:text;color:transparent}
.card,.stat{background:linear-gradient(160deg,var(--surface),#121528)}
.stat b{text-shadow:0 0 24px var(--accent)}
.timeline li::before{box-shadow:0 0 12px var(--accent)}
''',
  ),
  WebsiteTheme(
    id: 'postcard',
    name: 'Postcard',
    swatch: (0xFFF4EDE4, 0xFFD9480F),
    css: '''
body{--bg:#f4ede4;--surface:#fffaf3;--ink:#2d2620;--muted:#6f6357;--line:#e2d6c6;--radius:10px;--shadow:0 14px 30px -18px rgba(60,40,20,.5);--head:"Avenir Next","Futura","Century Gothic",system-ui,sans-serif;--body:"Avenir Next",system-ui,-apple-system,sans-serif;--head-weight:700}
.page{padding-top:20px}
.hero{background:var(--surface);border-radius:var(--radius);padding:36px 24px;margin-bottom:40px;box-shadow:var(--shadow);border:10px solid #fff;outline:2px dashed var(--accent);outline-offset:-18px}
.kicker::after{content:" \\2709"}
figure img{border:10px solid #fff;border-bottom-width:36px;border-radius:2px;box-shadow:var(--shadow)}
.gallery figure:nth-child(odd) img{transform:rotate(-1.5deg)}
.gallery figure:nth-child(even) img{transform:rotate(1.2deg)}
.card{border:0;box-shadow:var(--shadow)}
''',
  ),
];

WebsiteTheme websiteTheme(String id) =>
    websiteThemes.firstWhere((t) => t.id == id, orElse: () => websiteThemes[0]);

/// The full stylesheet for [theme] with [accent].
String websiteCss(WebsiteTheme theme) => '$_base$_accents${theme.css}';
