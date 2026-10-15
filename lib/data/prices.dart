import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'json_file.dart';

/// Prices are Cardmarket EUR (Scryfall's `eur` price comes from Cardmarket),
/// shown in GBP using the ECB daily rate from frankfurter. The rate is cached,
/// so prices still show offline.
class Fx extends ChangeNotifier {
  static final Fx instance = Fx._();
  Fx._();

  /// Fallback until the first successful fetch.
  double eurToGbp = 0.85;
  DateTime? fetched;
  final JsonFile _file = JsonFile('fx.json');

  Future<void> load() async {
    final data = await _file.open();
    if (data is Map) {
      eurToGbp = (data['rate'] as num?)?.toDouble() ?? eurToGbp;
      fetched = DateTime.tryParse(data['fetched'] as String? ?? '');
    }
    if (fetched == null || DateTime.now().difference(fetched!) > const Duration(hours: 24)) {
      refresh();
    }
  }

  Future<void> refresh() async {
    const urls = [
      'https://api.frankfurter.app/latest?from=EUR&to=GBP',
      'https://api.frankfurter.dev/v1/latest?base=EUR&symbols=GBP',
    ];
    for (final u in urls) {
      try {
        final res = await http.get(Uri.parse(u)).timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) continue;
        final rate = ((jsonDecode(res.body) as Map)['rates'] as Map)['GBP'] as num?;
        if (rate == null) continue;
        eurToGbp = rate.toDouble();
        fetched = DateTime.now();
        await _file.write({'rate': eurToGbp, 'fetched': fetched!.toIso8601String()});
        notifyListeners();
        return;
      } catch (_) {
        // offline or blocked: keep the cached rate
      }
    }
  }

  double gbp(double eur) => eur * eurToGbp;
}

/// "£12.34" from a EUR amount, or '' when there's no price.
String gbp(double? eur) => eur == null ? '' : '£${Fx.instance.gbp(eur).toStringAsFixed(2)}';
