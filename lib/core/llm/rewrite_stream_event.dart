import 'rewrite_result.dart';

/// [LlmClient.rewriteStream] 推送的中间态 / 完成态。
sealed class RewriteStreamEvent {}

class RewriteStreamPartial extends RewriteStreamEvent {
  RewriteStreamPartial({
    required this.answerAccumulated,
  });
  final String answerAccumulated;
}

class RewriteStreamCompleted extends RewriteStreamEvent {
  RewriteStreamCompleted.json(this.result) : plainText = null;
  RewriteStreamCompleted.text(this.plainText) : result = null;

  final LlmRewriteResult? result;
  final String? plainText;
}

class RewriteStreamFailed extends RewriteStreamEvent {
  RewriteStreamFailed(this.message);
  final String message;
}
