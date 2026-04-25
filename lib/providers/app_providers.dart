import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/llm/llm_client.dart';
import '../data/app_database.dart';
import '../data/history_repository.dart';
import '../data/kv_repository.dart';
import '../data/mode_repository.dart';
import '../data/secure_credential_store.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw StateError('AppDatabase 未注入');
});

final secureCredentialStoreProvider = Provider<SecureCredentialStore>((ref) {
  throw StateError('SecureCredentialStore 未注入');
});

final kvRepositoryProvider = Provider<KvRepository>((ref) {
  throw StateError('KvRepository 未注入');
});

final modeRepositoryProvider = Provider<ModeRepository>((ref) {
  return ModeRepository(ref.watch(appDatabaseProvider));
});

final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  return HistoryRepository(ref.watch(appDatabaseProvider));
});

final llmClientProvider = Provider<LlmClient>((ref) {
  throw StateError('LlmClient 未注入');
});

final modesRefreshProvider = StateProvider<int>((ref) => 0);

void bumpModesRefresh(WidgetRef ref) {
  ref.read(modesRefreshProvider.notifier).state++;
}
