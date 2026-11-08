import 'doc_block.dart';
import 'doc_inline.dart';

class DocTocEntry {
  final String id;
  final String title;
  final int level;

  const DocTocEntry({
    required this.id,
    required this.title,
    required this.level,
  });

  factory DocTocEntry.fromJson(Map<String, dynamic> json) {
    return DocTocEntry(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      level: json['level'] as int? ?? 2,
    );
  }
}

class DocPage {
  final String slug;
  final String number;
  final String title;
  final List<DocInline> lede;
  final List<DocTocEntry> toc;
  final List<DocBlock> blocks;

  const DocPage({
    required this.slug,
    required this.number,
    required this.title,
    required this.lede,
    required this.toc,
    required this.blocks,
  });

  factory DocPage.fromJson(Map<String, dynamic> json) {
    final slug = json['slug'] as String? ?? '';
    final number = json['number'] as String? ?? '';
    final title = json['title'] as String? ?? '';
    final lede = DocInline.fromList(json['lede'] as List<dynamic>?);

    final rawToc = (json['toc'] as List<dynamic>?) ?? [];
    final toc = rawToc.map((t) => DocTocEntry.fromJson(t as Map<String, dynamic>)).toList();

    final blocks = DocBlock.fromList(json['blocks'] as List<dynamic>?);

    return DocPage(
      slug: slug,
      number: number,
      title: title,
      lede: lede,
      toc: toc,
      blocks: blocks,
    );
  }
}
