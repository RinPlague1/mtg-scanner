import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config.dart';
import 'data/prices.dart';
import 'services.dart';
import 'ui/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  try {
    await Fx.instance.load();
    final services = await AppServices.create();
    runApp(BinderApp(services: services));
  } catch (e, st) {
    // Never sit on the launch screen: show what went wrong instead.
    debugPrint('startup failed: $e\n$st');
    runApp(_StartupError('$e'));
  }
}

class _StartupError extends StatelessWidget {
  final String message;
  const _StartupError(this.message);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ListView(children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              const Text('The app couldn\'t start', style: TextStyle(fontSize: 20)),
              const SizedBox(height: 12),
              SelectableText(message),
            ]),
          ),
        ),
      ),
    );
  }
}

class BinderApp extends StatelessWidget {
  final AppServices services;
  const BinderApp({super.key, required this.services});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7E57C2),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      // Android 15+ draws apps edge-to-edge, under the system Home / Back
      // buttons. Pad every screen (and bottom sheet) above them, and fill the
      // strip behind the buttons with the app's colour.
      builder: (context, child) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: SafeArea(top: false, left: false, right: false, child: child!),
      ),
      home: HomeShell(services: services),
    );
  }
}
