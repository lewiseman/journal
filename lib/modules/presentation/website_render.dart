import 'dart:convert';

import 'package:html/parser.dart' as html;

import 'website_contract.dart';
import 'website_themes.dart';

/// Where a themed page keeps its [WebsiteSpec], so any device can re-theme it
/// without the model. Older devices ignore the tag.
const websiteSpecMeta = 'journal-website';

String _escape(String text) => const HtmlEscape().convert(text);

/// Paragraphs from [text]'s blank-line-separated blocks; single newlines
/// become line breaks.
String _paragraphs(String text) => [
  for (final block in text.trim().split(RegExp(r'\n\s*\n')))
    if (block.trim().isNotEmpty)
      '<p>${_escape(block.trim()).replaceAll('\n', '<br>')}</p>',
].join();

String _photo(int index, [String caption = '']) =>
    '<figure><img data-photo="$index" alt="">'
    '${caption.isEmpty ? '' : '<figcaption>${_escape(caption)}</figcaption>'}'
    '</figure>';

String _section(WebsiteSection s) {
  final heading = s.heading.isEmpty ? '' : '<h2>${_escape(s.heading)}</h2>';
  final items = s.items;
  final photo = s.photo >= 0 && s.kind != 'photos' ? _photo(s.photo) : '';
  // Small models often repeat the items in the body; show them once.
  final intro =
      items.isNotEmpty && items.every((i) => s.body.contains(i.text.trim()))
      ? ''
      : _paragraphs(s.body);
  final body = switch (s.kind) {
    'cards' =>
      '$intro<div class="cards">${[for (final i in items) '<article class="card"><h3>${_escape(i.title)}</h3>${i.text.isEmpty ? '' : '<p>${_escape(i.text)}</p>'}</article>'].join()}</div>',
    'list' =>
      '$intro<ul class="list">${[for (final i in items) '<li>${i.title.isEmpty ? '' : '<strong>${_escape(i.title)}</strong> '}${_escape(i.text)}</li>'].join()}</ul>',
    'timeline' =>
      '$intro<ol class="timeline">${[for (final i in items) '<li><span class="when">${_escape(i.title)}</span><p>${_escape(i.text)}</p></li>'].join()}</ol>',
    'stats' =>
      '$intro<div class="stats">${[for (final i in items) '<div class="stat"><b>${_escape(i.title)}</b><span>${_escape(i.text)}</span></div>'].join()}</div>',
    'quote' =>
      '<blockquote>${_paragraphs(s.body.isEmpty && items.isNotEmpty ? items.first.text : s.body)}'
          '${s.heading.isEmpty ? '' : '<cite>${_escape(s.heading)}</cite>'}</blockquote>',
    // One chosen photo, or the whole gallery; the view drops placeholders
    // this device has no photo for. Items caption the photos in order.
    'photos' =>
      '$intro<div class="gallery">${[
        for (final (n, index) in (s.photo >= 0 ? [s.photo] : [for (var i = 0; i < websiteMaxPhotos; i++) i]).indexed) _photo(index, n < items.length ? items[n].text : ''),
      ].join()}</div>',
    _ => _paragraphs(s.body),
  };
  // A quote names its source in the cite, not a heading.
  return '<section class="s s-${s.kind}">${s.kind == 'quote' ? '' : heading}$photo$body</section>';
}

/// Draws [spec] as one self-contained page. Text is escaped, photos are
/// `data-photo` placeholders filled in by the view, and the spec rides along
/// in a meta tag when the page still fits the stored-website limit.
String renderWebsite(WebsiteSpec spec, {String title = ''}) {
  final theme = websiteTheme(spec.theme);
  final kicker = title.trim().isEmpty || title.trim() == spec.heading.trim()
      ? ''
      : '<p class="kicker">${_escape(title.trim())}</p>';
  String page(String meta) =>
      '<!doctype html><html lang="en"><head>$meta'
      '<title>${_escape(spec.heading)}</title>'
      '<style>${websiteCss(theme)}</style></head>'
      '<body class="t-${theme.id} a-${spec.accent}"><div class="page">'
      '<header class="hero">$kicker<h1>${_escape(spec.heading)}</h1>'
      '${spec.tagline.isEmpty ? '' : '<p class="tagline">${_escape(spec.tagline)}</p>'}</header>'
      '<main>${spec.sections.map(_section).join()}</main>'
      '<footer class="end">From my journal</footer>'
      '</div></body></html>';
  final full = page(
    '<meta name="$websiteSpecMeta" content="${_escape(spec.encode())}">',
  );
  // Leave room for the policy tags the sanitizer adds.
  return utf8.encode(full).length <= noteWebsiteOutputBytes ? full : page('');
}

/// The safe page for a finished website job: a themed spec is checked and
/// drawn here, a freehand page is only sanitized. [source] is the job's
/// encoded [WebsiteRequest]. Throws [FormatException] when unusable.
Future<String> websitePageFromOutput(
  String operation,
  String text, {
  String? source,
}) async {
  if (operation != noteWebsiteDesignOperation) {
    return sanitizeWebsiteBounded(text);
  }
  final request = source == null ? null : WebsiteRequest.decode(source);
  final spec = WebsiteSpec.decode(text, photos: request?.photos);
  return sanitizeWebsiteBounded(
    renderWebsite(spec, title: request?.title ?? ''),
  );
}

/// The spec a themed page was drawn from, or null for a freehand page.
WebsiteSpec? websiteSpecOf(String page) {
  try {
    final meta = html
        .parse(page)
        .querySelector('meta[name="$websiteSpecMeta"]')
        ?.attributes['content'];
    return meta == null ? null : WebsiteSpec.decode(meta);
  } on FormatException {
    return null;
  }
}
