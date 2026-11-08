/// The four parts of the Code Reference. Each is a short ladder of slices, from the smallest
/// building block up to the whole picture.
enum ReferenceCategory {
  violations('Violations', 'From one small question to all twenty rules'),
  pipelines('Pipelines', 'How a picture becomes a ticket'),
  training('Training', 'How a model is made, deployed and improved'),
  features('Features', 'What each button does, down to the code');

  const ReferenceCategory(this.title, this.blurb);
  final String title;
  final String blurb;
}

/// A place in the real source code: a file, and the line where the block starts (e.g. `def heading(`).
/// The code shown is read from the file when the slice is opened, so it can never go out of date.
class CodeAnchor {
  const CodeAnchor(this.file, this.symbol, {this.label = ''});

  /// Repository-relative path with forward slashes.
  final String file;

  /// The block starts at the first line that begins with this text (ignoring indentation).
  final String symbol;

  /// Name of the tab when a slice shows more than one place (e.g. `Dashboard`, `Backend`).
  final String label;

  bool get isDart => file.endsWith('.dart');
}

/// One thing to learn, shown on its own.
class Slice {
  const Slice({
    required this.id,
    required this.category,
    required this.group,
    required this.title,
    required this.short,
    required this.says,
    required this.code,
    this.recipe = const [],
    this.makes,
  });

  final String id;
  final ReferenceCategory category;

  /// The step of the ladder this belongs to (a small heading in the list).
  final String group;

  /// The question or name shown big.
  final String title;

  /// Two or three words, used when another slice lists this one as an ingredient.
  final String short;

  /// One or two plain sentences.
  final String says;

  /// Ids of the slices that are mixed together here: "this + this = that".
  final List<String> recipe;

  /// What the mix gives. Defaults to [title].
  final String? makes;

  final List<CodeAnchor> code;
}
