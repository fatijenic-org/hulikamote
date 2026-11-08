sealed class DocInline {
  const DocInline();

  static List<DocInline> fromList(List<dynamic>? list) {
    if (list == null) return const [];
    final out = <DocInline>[];
    for (final item in list) {
      if (item is Map<String, dynamic>) {
        final inline = DocInline.fromJson(item);
        if (inline != null) out.add(inline);
      }
    }
    return out;
  }

  static DocInline? fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'text';
    switch (type) {
      case 'text':
        return TextInline(json['text'] as String? ?? '');
      case 'b':
        return BoldInline(DocInline.fromList(json['children'] as List<dynamic>?));
      case 'i':
        return ItalicInline(DocInline.fromList(json['children'] as List<dynamic>?));
      case 's':
        return StrikeInline(DocInline.fromList(json['children'] as List<dynamic>?));
      case 'code':
        return CodeInline(json['text'] as String? ?? '');
      case 'link':
        return LinkInline(
          href: json['href'] as String? ?? '',
          children: DocInline.fromList(json['children'] as List<dynamic>?),
        );
      case 'term':
        return TermInline(
          key: json['key'] as String? ?? '',
          shown: json['shown'] as String? ?? '',
        );
      case 'chip':
        return ChipInline(
          kind: json['kind'] as String? ?? 'info',
          text: json['text'] as String? ?? '',
        );
      case 'br':
        return const BrInline();
      default:
        return TextInline(json['text'] as String? ?? '');
    }
  }

  String toPlainText();
}

class TextInline extends DocInline {
  final String text;
  const TextInline(this.text);

  @override
  String toPlainText() => text;
}

class BoldInline extends DocInline {
  final List<DocInline> children;
  const BoldInline(this.children);

  @override
  String toPlainText() => children.map((c) => c.toPlainText()).join();
}

class ItalicInline extends DocInline {
  final List<DocInline> children;
  const ItalicInline(this.children);

  @override
  String toPlainText() => children.map((c) => c.toPlainText()).join();
}

class StrikeInline extends DocInline {
  final List<DocInline> children;
  const StrikeInline(this.children);

  @override
  String toPlainText() => children.map((c) => c.toPlainText()).join();
}

class CodeInline extends DocInline {
  final String text;
  const CodeInline(this.text);

  @override
  String toPlainText() => text;
}

class LinkInline extends DocInline {
  final String href;
  final List<DocInline> children;
  const LinkInline({required this.href, required this.children});

  @override
  String toPlainText() => children.map((c) => c.toPlainText()).join();
}

class TermInline extends DocInline {
  final String key;
  final String shown;
  const TermInline({required this.key, required this.shown});

  @override
  String toPlainText() => shown;
}

class ChipInline extends DocInline {
  final String kind;
  final String text;
  const ChipInline({required this.kind, required this.text});

  @override
  String toPlainText() => '[$text]';
}

class BrInline extends DocInline {
  const BrInline();

  @override
  String toPlainText() => '\n';
}
