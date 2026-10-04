import 'package:flutter/material.dart';

import 'data/task_repository.dart';
import 'state/app_state.dart';
import 'services/notification_service.dart';
import 'ui/home_page.dart';
import 'ui/login_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.initialize();
  runApp(const ActionPlannerApp());
}

class ActionPlannerApp extends StatefulWidget {
  const ActionPlannerApp({super.key, this.repository});

  final TaskRepository? repository;

  @override
  State<ActionPlannerApp> createState() => _ActionPlannerAppState();
}

class _ActionPlannerAppState extends State<ActionPlannerApp> {
  late final AppState appState;

  @override
  void initState() {
    super.initState();
    appState = AppState(widget.repository ?? TaskRepository.create());
    appState.bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Làm việc thông minh',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF356859)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF6F7F2),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
      home: AnimatedBuilder(
        animation: appState,
        builder: (context, _) {
          if (appState.isBootstrapping) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return appState.isSignedIn
              ? HomePage(appState: appState)
              : LoginPage(appState: appState);
        },
      ),
    );
  }
}
