import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 必须被主程序引用，否则 release AOT 会 tree-shake 掉，OverlayService 第二引擎会报
// Dart_LookupLibrary: library 'lib/overlay_main.dart' not found。
// ignore: unused_import — 仅用于链接库，由原生按 entrypoint 加载，勿删。
import 'overlay_main.dart';

import 'app.dart';
import 'core/llm/llm_client.dart';
import 'data/app_database.dart';
import 'data/kv_repository.dart';
import 'data/secure_credential_store.dart';
import 'platform/overlay_bridge.dart';
import 'providers/app_providers.dart';
import 'router/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();
  final secure = SecureCredentialStore();
  final kv = KvRepository(db);
  final llm = LlmClient(credentials: secure);
  final router = createAppRouter();

  await kv.set('collect_dialog_enabled', await kv.get('collect_dialog_enabled') ?? '0');
  await kv.set('overlay_auto_show', await kv.get('overlay_auto_show') ?? '0');
  await kv.set('rewrite_output_count', await kv.get('rewrite_output_count') ?? '3');
  await OverlayBridge.syncOverlayPrefs(
    overlayAutoShow: await kv.get('overlay_auto_show') == '1',
    collectDialogEnabled: await kv.get('collect_dialog_enabled') == '1',
  );
  if (await kv.get('overlay_auto_show') == '1') {
    await OverlayBridge.showBubbleIfPermitted();
  }

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        secureCredentialStoreProvider.overrideWithValue(secure),
        kvRepositoryProvider.overrideWithValue(kv),
        llmClientProvider.overrideWithValue(llm),
      ],
      child: SpeechMirrorApp(router: router),
    ),
  );
}
