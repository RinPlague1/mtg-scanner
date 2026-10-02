import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/collection.dart';
import 'data/scryfall.dart';
import 'ui/scanner_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final collection = CollectionStore();
  await collection.load();
  runApp(DarkScannerApp(collection: collection, scryfall: ScryfallClient()));
}

class DarkScannerApp extends StatelessWidget {
  final CollectionStore collection;
  final ScryfallClient scryfall;
  const DarkScannerApp({super.key, required this.collection, required this.scryfall});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dark Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7E57C2),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: ScannerScreen(collection: collection, scryfall: scryfall),
    );
  }
}
