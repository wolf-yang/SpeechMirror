class RewriteVariant {
  const RewriteVariant({required this.label, required this.text});

  final String label;
  final String text;

  Map<String, String> toJson() => {'label': label, 'text': text};

  static RewriteVariant fromJson(Map<String, dynamic> m) {
    return RewriteVariant(
      label: m['label']! as String,
      text: m['text']! as String,
    );
  }
}

class LlmRewriteResult {
  const LlmRewriteResult({
    required this.variants,
    required this.rationale,
  });

  final List<RewriteVariant> variants;
  final String rationale;
}
