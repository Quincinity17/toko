import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:mustache_template/mustache.dart';

/// Template tidak bisa diproses. [message] siap ditampilkan.
class ReceiptTemplateError implements Exception {
  const ReceiptTemplateError(this.message);

  final String message;

  @override
  String toString() => 'ReceiptTemplateError: $message';
}

/// Mengubah template struk menjadi HTML siap dirender.
///
/// 1. Variabel Mustache diisi (`{{total}}`, `{{#barang}}…{{/barang}}`).
/// 2. Aturan CSS di `<style>` ditempel ke atribut `style` elemen yang cocok,
///    karena perender HTML (flutter_widget_from_html) hanya membaca style
///    inline. Selector apa pun yang didukung `querySelectorAll` bisa dipakai
///    (tag, `.kelas`, `#id`, keturunan, dll.); `body`/`html` berlaku untuk
///    pembungkus seluruh struk. Urutan: aturan yang lebih akhir menang, dan
///    style inline paling kuat.
class ReceiptHtml {
  const ReceiptHtml._();

  static String render(String template, Map<String, Object?> values) {
    final String filled;
    try {
      filled = Template(
        template,
        lenient: true,
        htmlEscapeValues: true,
      ).renderString(values);
    } on TemplateException catch (e) {
      throw ReceiptTemplateError('Baris ${e.line}: ${_translate(e.message)}');
    }
    return inlineCss(filled);
  }

  static String _translate(String message) {
    if (message.contains('Unclosed tag')) return 'tag {{…}} belum ditutup.';
    if (message.contains('Unclosed section') ||
        message.contains('Unclosed sections')) {
      return 'bagian {{#…}} belum ditutup dengan {{/…}}.';
    }
    if (message.contains('Mismatched tag')) {
      return 'penutup {{/…}} tidak cocok dengan pembukanya.';
    }
    return message;
  }

  /// Menempelkan aturan `<style>` ke elemen, lalu mengembalikan isi body
  /// dalam satu `<div>` pembungkus.
  static String inlineCss(String source) {
    final doc = html_parser.parse(source);
    final css = StringBuffer();
    for (final style in doc.querySelectorAll('style')) {
      css.writeln(style.text);
      style.remove();
    }

    final root = dom.Element.tag('div');
    final body = doc.body;
    if (body != null) root.nodes.addAll(body.nodes.toList());
    final wrapper = dom.Document.html('<html><body></body></html>');
    wrapper.body!.append(root);

    // Style inline asli disimpan dulu supaya tetap paling kuat.
    final original = <dom.Element, String>{
      for (final e in root.querySelectorAll('*'))
        if (e.attributes['style'] != null) e: e.attributes['style']!,
    };
    final applied = <dom.Element, Map<String, String>>{};
    void apply(dom.Element e, Map<String, String> decls) =>
        (applied[e] ??= {}).addAll(decls);

    for (final (selectors, decls) in parseCss(css.toString())) {
      for (final selector in selectors) {
        if (selector == 'body' || selector == 'html' || selector == ':root') {
          apply(root, decls);
          continue;
        }
        final List<dom.Element> matches;
        try {
          matches = root.querySelectorAll(selector);
        } catch (_) {
          continue; // selector tidak didukung: diabaikan seperti browser.
        }
        for (final e in matches) {
          apply(e, decls);
        }
      }
    }

    for (final MapEntry(key: e, value: decls) in applied.entries) {
      final css = decls.entries.map((d) => '${d.key}: ${d.value}').join('; ');
      final inline = original[e];
      e.attributes['style'] = inline == null ? css : '$css; $inline';
    }
    _browserFixes(root);
    return root.outerHtml;
  }

  /// Menyamakan dua perilaku browser yang tidak dilakukan perender:
  /// - anak langsung `display: flex` menjadi item terpisah (blockified),
  ///   supaya `<span>` kiri/kanan bisa dipisah `justify-content`;
  /// - elemen kosong yang punya border/tinggi (mis. garis pemisah) tetap
  ///   digambar, bukan dibuang.
  static void _browserFixes(dom.Element root) {
    for (final e in root.querySelectorAll('*')) {
      final style = (e.attributes['style'] ?? '').toLowerCase();
      if (RegExp(r'display\s*:\s*flex').hasMatch(style)) {
        for (final child in e.children) {
          final s = child.attributes['style'];
          if (s == null || !s.contains('display')) {
            child.attributes['style'] = s == null
                ? 'display: block'
                : 'display: block; $s';
          }
        }
      }
      final empty = e.nodes.every(
        (n) => n is dom.Text && n.text.trim().isEmpty,
      );
      const voidTags = {'img', 'br', 'hr', 'input'};
      if (empty &&
          !voidTags.contains(e.localName) &&
          RegExp(r'border|height').hasMatch(style)) {
        e.nodes
          ..clear()
          ..add(
            dom.Element.tag('span')
              ..attributes['style'] = 'font-size: 0px; line-height: 0'
              ..text = '​',
          );
      }
    }
  }

  /// Parser CSS sederhana: `selector, selector { prop: nilai; … }`.
  /// Komentar dibuang; at-rule (`@media`, `@page`, …) beserta isinya
  /// diabaikan.
  static List<(List<String>, Map<String, String>)> parseCss(String css) {
    final src = css.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    final rules = <(List<String>, Map<String, String>)>[];
    var i = 0;
    while (i < src.length) {
      final open = src.indexOf('{', i);
      if (open < 0) break;
      final selectorText = src.substring(i, open).trim();
      // Cari kurung tutup pasangannya (at-rule bisa bersarang).
      var depth = 1;
      var j = open + 1;
      while (j < src.length && depth > 0) {
        if (src[j] == '{') depth++;
        if (src[j] == '}') depth--;
        j++;
      }
      final body = src.substring(open + 1, depth == 0 ? j - 1 : j);
      i = j;
      if (selectorText.isEmpty || selectorText.startsWith('@')) continue;
      if (body.contains('{')) continue;

      final selectors = [
        for (final s in selectorText.split(','))
          if (s.trim().isNotEmpty) s.trim(),
      ];
      final decls = <String, String>{};
      for (final d in body.split(';')) {
        final k = d.indexOf(':');
        if (k <= 0) continue;
        final prop = d.substring(0, k).trim().toLowerCase();
        final value = d.substring(k + 1).trim();
        if (prop.isNotEmpty && value.isNotEmpty) decls[prop] = value;
      }
      if (selectors.isNotEmpty && decls.isNotEmpty) {
        rules.add((selectors, decls));
      }
    }
    return rules;
  }
}
