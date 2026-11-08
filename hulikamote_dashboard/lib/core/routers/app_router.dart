import 'package:go_router/go_router.dart';
import '../shell/app_shell.dart';
import '../../features/monitoring/presentation/screens/live_monitoring_screen.dart';
import '../../features/violations/presentation/screens/violations_screen.dart';
import '../../features/demerit/presentation/screens/demerit_screen.dart';
import '../../features/registry/presentation/screens/registry_screen.dart';
import '../../features/models_hub/presentation/screens/models_hub_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/violations/presentation/screens/inbox_screen.dart';
import '../../features/monitoring/presentation/screens/offline_video_screen.dart';
import '../../features/forensic/presentation/screens/forensic_analyzer_screen.dart';
import '../../features/benchmark/presentation/screens/benchmark_screen.dart';
import '../../features/monitoring/presentation/screens/video_utilities_screen.dart';
import '../../features/blueprint/presentation/screens/blueprint_screen.dart';
import '../../features/docs/presentation/screens/docs_screen.dart';
import '../../features/wiki/presentation/screens/wiki_screen.dart';
import '../../features/launcher/presentation/screens/launcher_screens.dart';
import '../../features/datasets/presentation/screens/dataset_viewer_screen.dart';
import '../../features/overview/presentation/screens/overview_screen.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    // The Training Studio is part of the Models page now; the old address still opens it.
    GoRoute(path: '/training', redirect: (context, state) => '/model'),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/', builder: (context, state) => const LiveMonitoringScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/offline-video', builder: (context, state) => const OfflineVideoScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/forensic-analyzer',
            builder: (context, state) =>
                ForensicAnalyzerScreen(initialTab: state.uri.queryParameters['tab'] == 'harvest' ? 2 : 0),
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/benchmark', builder: (context, state) => const BenchmarkScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/inbox', builder: (context, state) => const InboxScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/violations', builder: (context, state) => const ViolationsScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/demerit', builder: (context, state) => const DemeritScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/registry', builder: (context, state) => const RegistryScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/model', builder: (context, state) => ModelsHubScreen(initialJob: state.uri.queryParameters['job'])),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/utilities', builder: (context, state) => const VideoUtilitiesScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/wiki', builder: (context, state) => const WikiScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/blueprint', builder: (context, state) => const BlueprintScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/docs', builder: (context, state) => const DocsScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/progress-report', builder: (context, state) => const ProgressReportScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/visualizer', builder: (context, state) => const VisualizerScreen()),
        ]),
                  StatefulShellBranch(routes: [
                    GoRoute(path: '/datasets', builder: (context, state) => const DatasetViewerScreen()),
                  ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/overview', builder: (context, state) => const OverviewScreen()),
        ]),
      ],
    ),
  ],
);
