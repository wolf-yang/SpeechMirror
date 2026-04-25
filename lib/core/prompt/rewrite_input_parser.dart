class RewriteInputParseResult {
  const RewriteInputParseResult({
    required this.originalText,
    this.userHint,
  });

  final String originalText;
  final String? userHint;
}

class RewriteInputParser {
  static final RegExp _tailHintPattern = RegExp(
    r'^(.*?)(?:\s*[（(]([^（）()]*)[）)])\s*$',
    dotAll: true,
  );

  static RewriteInputParseResult parse(String rawInput) {
    final raw = rawInput.trim();
    if (raw.isEmpty) {
      return const RewriteInputParseResult(originalText: '');
    }
    final match = _tailHintPattern.firstMatch(raw);
    if (match == null) {
      return RewriteInputParseResult(originalText: raw);
    }
    final text = (match.group(1) ?? '').trim();
    final hint = (match.group(2) ?? '').trim();
    if (text.isEmpty || hint.isEmpty) {
      return RewriteInputParseResult(originalText: raw);
    }
    return RewriteInputParseResult(
      originalText: text,
      userHint: hint,
    );
  }
}
