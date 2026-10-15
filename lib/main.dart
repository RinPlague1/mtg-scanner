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
      home: HomeShell(services: services),
    );
  }
}
