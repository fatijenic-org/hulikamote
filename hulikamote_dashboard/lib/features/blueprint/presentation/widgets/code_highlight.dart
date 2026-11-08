import 'package:flutter/material.dart';

/// Light syntax colouring for the Code Reference: comments, strings, numbers, keywords, and the name being defined.
/// Five colours, nothing else. Lines are coloured on their own (a docstring is recognised by its triple quotes).
class CodeColors {
  CodeColors._();
  static const Color keyword = Color(0xFF7AA2F7);
  static const Color string = Color(0xFF9ECE6A);
  static const Color number = Color(0xFFE0AF68);
  static const Color comment = Color(0xFF6C7A89);
  static const Color name = Color(0xFFE6EDF3);
}

const _python = {
  'def', 'class', 'return', 'if', 'elif', 'else', 'for', 'while', 'in', 'not', 'and', 'or', 'is', 'None', 'True', 'False',
  'import', 'from', 'as', 'with', 'try', 'except', 'finally', 'raise', 'lambda', 'async', 'await', 'yield', 'continue',
  'break', 'pass', 'self',
};
const _dart = {
  'class', 'void', 'final', 'const', 'var', 'return', 'if', 'else', 'for', 'while', 'in', 'null', 'true', 'false',
  'import', 'as', 'try', 'catch', 'finally', 'throw', 'async', 'await', 'Future', 'static', 'late', 'extends', 'with',
  'switch', 'case', 'new', 'this', 'super', 'bool', 'int', 'double', 'String', 'is', 'required',
};

final _token = RegExp(
  r'''(?<comment>\#.*$|//.*$)|(?<string>[fFrRbB]?(?:'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*"))|(?<number>\b\d+(?:\.\d+)?\b)|(?<word>@?[A-Za-z_]\w*)''',
);

/// One list of spans per line. [base] is the text style of the code (font, size).
List<List<TextSpan>> highlight(List<String> lines, {required bool dart, required TextStyle base}) {
  final keywords = dart ? _dart : _python;
  final out = <List<TextSpan>>[];
  var inDocstring = false;
  for (final line in lines) {
    final triples = RegExp(r'"""|' "'''").allMatches(line).length;
    final docLine = !dart && (inDocstring || triples > 0);
    if (!dart && triples.isOdd) inDocstring = !inDocstring;
    if (docLine) {
      out.add([TextSpan(text: line, style: base.copyWith(color: CodeColors.comment))]);
      continue;
    }
    out.add(_line(line, keywords, base));
  }
  return out;
}

List<TextSpan> _line(String text, Set<String> keywords, TextStyle base) {
  final spans = <TextSpan>[];
  var at = 0;
  var afterDefinition = false; // the word after `def` / `class` is the name being defined
  for (final m in _token.allMatches(text)) {
    if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start), style: base));
    final piece = m.group(0)!;
    TextStyle style = base;
    if (m.namedGroup('comment') != null) {
      style = base.copyWith(color: CodeColors.comment);
    } else if (m.namedGroup('string') != null) {
      style = base.copyWith(color: CodeColors.string);
    } else if (m.namedGroup('number') != null) {
      style = base.copyWith(color: CodeColors.number);
    } else if (keywords.contains(piece) || piece.startsWith('@')) {
      style = base.copyWith(color: CodeColors.keyword);
      afterDefinition = piece == 'def' || piece == 'class';
      spans.add(TextSpan(text: piece, style: style));
      at = m.end;
      continue;
    } else if (afterDefinition) {
      style = base.copyWith(color: CodeColors.name, fontWeight: FontWeight.w700);
    }
    afterDefinition = false;
    spans.add(TextSpan(text: piece, style: style));
    at = m.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at), style: base));
  return spans;
}
