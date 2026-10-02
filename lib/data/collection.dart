import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'scryfall.dart';

class CollectionEntry {
  final CardPrint card;
  final bool foil;
  int quantity;
  final DateTime added;

  CollectionEntry(this.card, {this.foil = false, this.quantity = 1, DateTime? added})
      : added = added ?? DateTime.now();

  String get key => '${card.id}|${foil ? 'f' : 'n'}';

  double? get priceEur => double.tryParse((foil ? card.priceEurFoil : card.priceEur) ?? '');
  double? get priceUsd => double.tryParse((foil ? card.priceUsdFoil : card.priceUsd) ?? '');

  Map<String, dynamic> toJson() => {
        'card': card.toJson(),
        'foil': foil,
        'quantity': quantity,
        'added': added.toIso8601String(),
      };

  factory CollectionEntry.fromJson(Map<String, dynamic> j) => CollectionEntry(
        CardPrint.fromScryfall(j['card'] as Map<String, dynamic>),
        foil: j['foil'] as bool? ?? false,
        quantity: j['quantity'] as int? ?? 1,
        added: DateTime.tryParse(j['added'] as String? ?? ''),
      );
}

/// Local collection persisted as JSON in the app's documents folder.
class CollectionStore extends ChangeNotifier {
  final List<CollectionEntry> _entries = [];
  File? _file;

  List<CollectionEntry> get entries => List.unmodifiable(_entries);
  int get totalCards => _entries.fold(0, (s, e) => s + e.quantity);
  double get totalEur => _entries.fold(0.0, (s, e) => s + (e.priceEur ?? 0) * e.quantity);

  Future<void> load() async {
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/collection.json');
    if (await _file!.exists()) {
      final list = jsonDecode(await _file!.readAsString()) as List;
      _entries
        ..clear()
        ..addAll(list.map((e) => CollectionEntry.fromJson(e as Map<String, dynamic>)));
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final f = _file;
    if (f == null) return;
    await f.writeAsString(jsonEncode(_entries.map((e) => e.toJson()).toList()));
  }

  Future<void> add(CardPrint card, {bool foil = false, int quantity = 1}) async {
    final key = '${card.id}|${foil ? 'f' : 'n'}';
    final i = _entries.indexWhere((e) => e.key == key);
    if (i >= 0) {
      _entries[i].quantity += quantity;
      final e = _entries.removeAt(i);
      _entries.insert(0, e); // most recent first
    } else {
      _entries.insert(0, CollectionEntry(card, foil: foil, quantity: quantity));
    }
    notifyListeners();
    await _save();
  }

  Future<void> setQuantity(CollectionEntry e, int q) async {
    if (q <= 0) {
      _entries.remove(e);
    } else {
      e.quantity = q;
    }
    notifyListeners();
    await _save();
  }

  /// Moxfield-compatible CSV (also accepted by most other collection sites).
  String toMoxfieldCsv() {
    String esc(String s) => '"${s.replaceAll('"', '""')}"';
    final b = StringBuffer('"Count","Name","Edition","Condition","Language","Foil","Collector Number"\n');
    for (final e in _entries.reversed) {
      b.writeln([
        esc('${e.quantity}'),
        esc(e.card.name),
        esc(e.card.setCode),
        esc('Near Mint'),
        esc('English'),
        esc(e.foil ? 'foil' : ''),
        esc(e.card.collectorNumber),
      ].join(','));
    }
    return b.toString();
  }

  Future<File> exportCsv() async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final f = File('${dir.path}/collection-$stamp.csv');
    await f.writeAsString(toMoxfieldCsv());
    return f;
  }
}
