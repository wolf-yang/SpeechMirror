import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/models/mode_entity.dart';
import '../features/distill/distill_screen.dart';
import '../features/history/history_screen.dart';
import '../features/home/home_screen.dart';
import '../features/modes/ai_create_mode_screen.dart';
import '../features/modes/create_mode_screen.dart';
import '../features/modes/mode_detail_screen.dart';
import '../features/modes/modes_screen.dart';
import '../features/profile/llm_settings_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/shell/main_shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

GoRouter createAppRouter() {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/home',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/modes',
                builder: (context, state) => const ModesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/distill',
                builder: (context, state) => const DistillScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/modes/create',
        builder: (context, state) {
          final initial = state.extra as ModeEntity?;
          return CreateModeScreen(initial: initial);
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/modes/ai-create',
        builder: (context, state) => const AiCreateModeScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/modes/:id',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          return ModeDetailScreen(modeId: id);
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/settings/llm',
        builder: (context, state) => const LlmSettingsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/history',
        builder: (context, state) => const HistoryScreen(),
      ),
    ],
  );
}
