import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config.dart';
import 'data/prices.dart';
import 'services.dart';
import 'ui/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Fx.instance.load();
  final services = await AppServices.create();
  runApp(BinderApp(services: services));
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
