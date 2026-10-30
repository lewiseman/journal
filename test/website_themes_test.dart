import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/notes/models/note_attachment.dart';
import 'package:journal/modules/presentation/website_assets.dart';
import 'package:journal/modules/presentation/website_contract.dart';
import 'package:journal/modules/presentation/website_render.dart';
import 'package:journal/modules/presentation/website_themes.dart';

Map<String, Object> _section(
  String kind, {
  String heading = '',
  String body = '',
  List<Map<String, String>> items = const [],
  int photo = -1,
}) => {
  'kind': kind,
  'heading': heading,
  'body': body,
  'items': items,
  'photo': photo,
};

final _items = [
  {'title': 'May 3', 'text': 'Seeds in'},
  {'title': 'June', 'text': 'First tomatoes'},
];

Map<String, Object> _spec({String theme = 'garden', List<Object>? sections}) =>
    {
      'theme': theme,
      'accent': 'forest',
      'hero': {'heading': 'Garden plan', 'tagline': 'A small season'},
      'sections':
          sections ??
          [
            _section('text', heading: 'Why', body: 'Fresh food.\n\nAnd calm.'),
            _section('cards', heading: 'Beds', items: _items),
            _section('list', items: _items),
            _section('timeline', heading: 'When', items: _items),
            _section('quote', heading: 'Gran', body: 'Water at dawn.'),
            _section('stats', items: _items),
            _section('photos', heading: 'Photos', items: _items),
            _section('text', body: 'With a photo', photo: 1),
          ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a spec within the contract decodes and round-trips', () {
    final spec = WebsiteSpec.decode(jsonEncode(_spec()), photos: 2);
    expect(spec.sections, hasLength(8));
    expect(WebsiteSpec.decode(spec.encode()).encode(), spec.encode());
    expect(
      WebsiteSpec.decode('```json\n${jsonEncode(_spec())}\n```').heading,
      'Garden plan',
    );
  });

  test('specs outside the contract are rejected', () {
    final bad = <Object>[
      {..._spec(), 'theme': 'neon'},
      {..._spec(), 'accent': 'teal'},
      {..._spec(), 'extra': 1},
      _spec(sections: []),
      _spec(sections: List.filled(9, _section('text', body: 'x'))),
      _spec(sections: [_section('marquee', body: 'x')]),
      _spec(sections: [_section('text', body: 'x' * 601)]),
      _spec(sections: [_section('text', heading: 'a\nb')]),
      _spec(
        sections: [
          _section('list', items: List.filled(7, {'title': 'a', 'text': 'b'})),
        ],
      ),
    ];
    for (final value in bad) {
      expect(
        () => WebsiteSpec.decode(jsonEncode(value)),
        throwsFormatException,
        reason: jsonEncode(value),
      );
    }
    expect(() => WebsiteSpec.decode('not json'), throwsFormatException);
    // A photo the note does not have.
    expect(
      () => WebsiteSpec.decode(jsonEncode(_spec()), photos: 1),
      throwsFormatException,
    );
  });

  test('every theme renders a safe page within the stored limit', () async {
    for (final theme in websiteThemes) {
      final spec = WebsiteSpec.decode(jsonEncode(_spec(theme: theme.id)));
      final raw = renderWebsite(spec, title: 'My garden');
      final page = await sanitizeWebsiteBounded(raw);
      expect(utf8.encode(page).length, lessThan(noteWebsiteOutputBytes + 1024));
      expect(page, contains('class="t-${theme.id} a-forest"'));
      expect(page, contains('data-photo="1"'));
      expect(page, isNot(contains('<script')));
      // The spec survives sanitizing, so the page can be re-themed.
      expect(websiteSpecOf(page)?.encode(), spec.encode());
    }
  });

  test('note text is escaped, never markup', () {
    final spec = WebsiteSpec.decode(
      jsonEncode(
        _spec(
          sections: [
            _section('text', heading: '<b>x</b>', body: '<script>1</script>'),
          ],
        ),
      ),
    );
    final page = renderWebsite(spec);
    expect(page, isNot(contains('<script>1')));
    expect(page, contains('&lt;script&gt;1&lt;&#47;script&gt;'));
    expect(page, contains('<h2>&lt;b&gt;x&lt;&#47;b&gt;</h2>'));
  });

  test('body text the items repeat is shown once', () {
    final spec = WebsiteSpec.decode(
      jsonEncode(
        _spec(
          sections: [
            _section(
              'timeline',
              body: 'May 3: Seeds in\nJune: First tomatoes',
              items: _items,
            ),
            _section('list', body: 'Our plan', items: _items),
          ],
        ),
      ),
    );
    final page = renderWebsite(spec);
    expect(page, isNot(contains('<p>May 3: Seeds in')));
    expect(page, contains('<span class="when">May 3</span><p>Seeds in</p>'));
    expect(page, contains('<p>Our plan</p>'));
  });

  test('freehand jobs are only sanitized; themed jobs are drawn', () async {
    const freehand =
        '<!doctype html><html><head></head><body><h1>Hi</h1></body></html>';
    expect(
      await websitePageFromOutput(noteWebsiteOperation, freehand),
      contains('<h1>Hi</h1>'),
    );
    final source = const WebsiteRequest(
      noteId: 'n',
      version: '{}',
      title: 'Garden',
      content: 'Tomatoes',
      description: 'Calm',
      theme: 'auto',
      photos: 2,
    ).encode();
    final page = await websitePageFromOutput(
      noteWebsiteDesignOperation,
      jsonEncode(_spec()),
      source: source,
    );
    expect(page, contains('<p class="kicker">Garden</p>'));
    await expectLater(
      websitePageFromOutput(
        noteWebsiteDesignOperation,
        jsonEncode(_spec()),
        source: source.replaceFirst('"photos":2', '"photos":1'),
      ),
      throwsFormatException,
    );
  });

  test('themed requests carry theme and photo count, not photos', () {
    const request = WebsiteRequest(
      noteId: 'n',
      version: '{}',
      title: 'T',
      content: 'Body',
      description: 'Calm',
      theme: 'zine',
      photos: 3,
    );
    expect(request.operation, noteWebsiteDesignOperation);
    expect(jsonDecode(request.request()), {
      'title': 'T',
      'text': 'Body',
      'description': 'Calm',
      'theme': 'zine',
      'photos': 3,
    });
    final decoded = WebsiteRequest.decode(request.encode());
    expect((decoded.theme, decoded.photos), ('zine', 3));
    expect(
      () => const WebsiteRequest(
        noteId: 'n',
        version: '{}',
        title: '',
        content: 'Body',
        description: 'Calm',
        theme: 'neon',
      ).request(),
      throwsFormatException,
    );
    // Freehand requests are unchanged for older computers.
    const freehand = WebsiteRequest(
      noteId: 'n',
      version: '{}',
      title: '',
      content: 'Body',
      description: 'Calm',
    );
    expect(freehand.operation, noteWebsiteOperation);
    expect(
      (jsonDecode(freehand.request()) as Map).keys,
      unorderedEquals(['title', 'text', 'description']),
    );
  });

  test('photos fill placeholders; missing ones are removed', () async {
    final dir = await Directory.systemTemp.createTemp('website-photos');
    addTearDown(() => dir.delete(recursive: true));
    // A 1x1 PNG.
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
    );
    final file = File('${dir.path}/a.png')..writeAsBytesSync(png);
    final photos = [
      NoteAttachment(path: file.path, type: 'image/png'),
      NoteAttachment(path: '${dir.path}/gone.jpg', type: 'image/jpeg'),
    ];
    final safe = await sanitizeWebsiteBounded(
      renderWebsite(WebsiteSpec.decode(jsonEncode(_spec(theme: 'zine')))),
    );
    final page = await withWebsiteAssets(safe, photos);
    expect(page, contains('src="data:image/png;base64,'));
    expect(page, isNot(contains('data-photo="1"')));
    expect(page, isNot(contains('data-photo="5"')));
    expect(page, contains('data-photo="0"'));
  });

  test('themes that name a bundled font embed it', () async {
    final safe = await sanitizeWebsiteBounded(
      renderWebsite(WebsiteSpec.decode(jsonEncode(_spec(theme: 'notebook')))),
    );
    final page = await withWebsiteAssets(safe, const []);
    expect(page, contains('font-family:"Caveat"'));
    expect(page, contains('url(data:font/ttf;base64,'));
  });

  test('only image attachments count as photos, at most six', () {
    expect(
      websitePhotos([
        for (var i = 0; i < 8; i++) {'path': '/p/$i.jpg', 'type': 'image/jpeg'},
        {'path': '/p/doc.pdf', 'type': 'application/pdf'},
      ]),
      hasLength(6),
    );
  });
}
