import 'dart:convert';
import 'dart:io';

import 'reference_models.dart';

/// A block of real source code and where it sits in its file.
class CodeSnippet {
  const CodeSnippet({required this.file, required this.startLine, required this.lines, required this.truncated});

  final String file;

  /// 1-based line number of the first line (the one a code editor should open at).
  final int startLine;
  final List<String> lines;

  /// More lines exist than were kept.
  final bool truncated;
}

/// Finds a function or class in a source file and returns its lines. Pure text work, so it is quick and
/// needs no parser: Python blocks end where the indentation falls back, Dart blocks where the braces balance.
class CodeReader {
  CodeReader._();

  static const int maxLines = 120;

  /// Reads [anchor] from the repository at [root]. Null when the file or the symbol cannot be found.
  static CodeSnippet? read(Directory root, CodeAnchor anchor) {
    final file = File('${root.path}${Platform.pathSeparator}${anchor.file.replaceAll('/', Platform.pathSeparator)}');
    if (!file.existsSync()) return null;
    return extract(file.readAsStringSync(), anchor.symbol, dart: anchor.isDart, file: anchor.file);
  }

  static CodeSnippet? extract(String source, String symbol, {required bool dart, String file = ''}) {
    final all = const LineSplitter().convert(source);
    final start = all.indexWhere((l) => l.trimLeft().startsWith(symbol));
    if (start < 0) return null;

    var first = start;
    while (first > 0 && all[first - 1].trimLeft().startsWith('@')) {
      first--; // decorators belong to the function below them
    }
    final end = dart ? _dartEnd(all, start) : _pythonEnd(all, start);

    var lines = all.sublist(first, end + 1);
    final truncated = lines.length > maxLines;
    if (truncated) lines = lines.sublist(0, maxLines);
    return CodeSnippet(file: file, startLine: first + 1, lines: _trimIndent(lines), truncated: truncated);
  }

  static int _indent(String line) => line.length - line.trimLeft().length;

  static int _pythonEnd(List<String> all, int start) {
    // A signature can run over several lines; the body starts after the line that ends with ':'.
    var body = start;
    final colon = RegExp(r':\s*(#.*)?$');
    while (body < all.length - 1 && !colon.hasMatch(all[body].trimRight())) {
      body++;
    }
    final base = _indent(all[start]);
    var end = body;
    for (var i = body + 1; i < all.length; i++) {
      final line = all[i];
      if (line.trim().isEmpty) continue;
      if (_indent(line) <= base) break;
      end = i;
    }
    return end;
  }

  static int _dartEnd(List<String> all, int start) {
    var depth = 0;
    var opened = false;
    for (var i = start; i < all.length; i++) {
      final code = all[i].split('//').first;
      for (final unit in code.codeUnits) {
        if (unit == 0x7B) {
          depth++;
          opened = true;
        } else if (unit == 0x7D) {
          depth--;
        }
      }
      if (opened && depth <= 0) return i;
      if (!opened && code.trimRight().endsWith(';')) return i; // a one-line member
    }
    return all.length - 1;
  }

  /// Removes the indentation shared by every line, so a method shows flush left.
  static List<String> _trimIndent(List<String> lines) {
    final indents = lines.where((l) => l.trim().isNotEmpty).map(_indent);
    if (indents.isEmpty) return lines;
    final common = indents.reduce((a, b) => a < b ? a : b);
    return [for (final l in lines) l.length >= common ? l.substring(common) : l.trimLeft()];
  }
}
