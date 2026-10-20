import 'package:flutter/material.dart';

import '../data/settings.dart';
import 'widgets.dart';

/// Seed colour for each colour of Magic, tuned to read well on a dark UI.
const _mana = <String, Color>{
  'W': Color(0xFFE9DDAF),
  'U': Color(0xFF2F80ED),
  'B': Color(0xFF7A5C8E),
  'R': Color(0xFFE0533D),
  'G': Color(0xFF2E9A5B),
  'C': Color(0xFF9E9E9E),
};

/// An app colour theme named after an MTG colour combination.
class MtgTheme {
  final String id;
  final String name;
  final String colours; // e.g. "UR"
  final String group;
  const MtgTheme(this.id, this.name, this.colours, this.group);

  List<Color> get swatch => [for (final c in colours.split('')) _mana[c]!];
}

const mtgThemes = <MtgTheme>[
  MtgTheme('default', 'Dark Scanner', '', 'Default'),
  MtgTheme('white', 'White', 'W', 'Mono'),
  MtgTheme('blue', 'Blue', 'U', 'Mono'),
  MtgTheme('black', 'Black', 'B', 'Mono'),
  MtgTheme('red', 'Red', 'R', 'Mono'),
  MtgTheme('green', 'Green', 'G', 'Mono'),
  MtgTheme('colourless', 'Colourless', 'C', 'Mono'),
  MtgTheme('azorius', 'Azorius', 'WU', 'Guilds'),
  MtgTheme('dimir', 'Dimir', 'UB', 'Guilds'),
  MtgTheme('rakdos', 'Rakdos', 'BR', 'Guilds'),
  MtgTheme('gruul', 'Gruul', 'RG', 'Guilds'),
  MtgTheme('selesnya', 'Selesnya', 'GW', 'Guilds'),
  MtgTheme('orzhov', 'Orzhov', 'WB', 'Guilds'),
  MtgTheme('izzet', 'Izzet', 'UR', 'Guilds'),
  MtgTheme('golgari', 'Golgari', 'BG', 'Guilds'),
  MtgTheme('boros', 'Boros', 'RW', 'Guilds'),
  MtgTheme('simic', 'Simic', 'GU', 'Guilds'),
  MtgTheme('esper', 'Esper', 'WUB', 'Shards'),
  MtgTheme('grixis', 'Grixis', 'UBR', 'Shards'),
  MtgTheme('jund', 'Jund', 'BRG', 'Shards'),
  MtgTheme('naya', 'Naya', 'RGW', 'Shards'),
  MtgTheme('bant', 'Bant', 'GWU', 'Shards'),
  MtgTheme('abzan', 'Abzan', 'WBG', 'Wedges'),
  MtgTheme('jeskai', 'Jeskai', 'URW', 'Wedges'),
  MtgTheme('sultai', 'Sultai', 'BGU', 'Wedges'),
  MtgTheme('mardu', 'Mardu', 'RWB', 'Wedges'),
  MtgTheme('temur', 'Temur', 'GUR', 'Wedges'),
  MtgTheme('five', 'Five-colour', 'WUBRG', 'Five-colour'),
];

MtgTheme themeById(String id) => mtgThemes.firstWhere((t) => t.id == id, orElse: () => mtgThemes.first);

/// Dark Material theme: the first colour drives the main accents, the
/// second and third the secondary/tertiary ones (chips, nav highlight…).
ThemeData buildAppTheme(String id) {
  final t = themeById(id);
  final colours = t.colours.isEmpty ? const [Color(0xFF7E57C2)] : t.swatch;
  ColorScheme seed(Color c) => ColorScheme.fromSeed(seedColor: c, brightness: Brightness.dark);
  var scheme = seed(colours.first);
  if (colours.length >= 2) {
    final s = seed(colours[1]);
    scheme = scheme.copyWith(
      secondary: s.primary,
      onSecondary: s.onPrimary,
      secondaryContainer: s.primaryContainer,
      onSecondaryContainer: s.onPrimaryContainer,
    );
  }
  if (colours.length >= 3) {
    final s = seed(colours[2]);
    scheme = scheme.copyWith(
      tertiary: s.primary,
      onTertiary: s.onPrimary,
      tertiaryContainer: s.primaryContainer,
      onTertiaryContainer: s.onPrimaryContainer,
    );
  }
  return ThemeData(colorScheme: scheme, useMaterial3: true);
}

/// Pick an app theme, grouped like the colour pie.
class ThemePickerScreen extends StatelessWidget {
  final AppSettings settings;
  const ThemePickerScreen({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<MtgTheme>>{};
    for (final t in mtgThemes) {
      groups.putIfAbsent(t.group, () => []).add(t);
    }
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Colour theme')),
        body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          for (final g in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(g.key, style: Theme.of(context).textTheme.titleSmall),
            ),
            for (final t in g.value)
              ListTile(
                leading: _Swatch(t),
                title: Text(t.name),
                subtitle: t.colours.isEmpty ? const Text('The original purple') : null,
                trailing: t.colours.isEmpty
                    ? null
                    : ManaCost(t.colours.split('').map((c) => '{$c}').join(), size: 16),
                selected: settings.theme == t.id,
                onTap: () => settings.setTheme(t.id),
              ),
          ],
        ]),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final MtgTheme theme;
  const _Swatch(this.theme);

  @override
  Widget build(BuildContext context) {
    final colours = theme.colours.isEmpty ? const [Color(0xFF7E57C2)] : theme.swatch;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: 36,
        height: 36,
        child: Row(children: [for (final c in colours) Expanded(child: ColoredBox(color: c))]),
      ),
    );
  }
}
