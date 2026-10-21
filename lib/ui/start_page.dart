import 'package:flutter/material.dart';

import '../data/settings.dart';

/// Lets the user choose which page the app opens on.
Future<void> showStartPagePicker(BuildContext context, AppSettings settings) async {
  final id = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Open the app on'),
      children: [
        RadioGroup<String>(
          groupValue: settings.startPage,
          onChanged: (v) => Navigator.pop(ctx, v),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final p in startPages) RadioListTile<String>(value: p.id, title: Text(p.label)),
          ]),
        ),
      ],
    ),
  );
  if (id != null) await settings.setStartPage(id);
}

/// Label of the current start page, for menus.
String startPageLabel(AppSettings settings) =>
    startPages.firstWhere((p) => p.id == settings.startPage, orElse: () => startPages[1]).label;
