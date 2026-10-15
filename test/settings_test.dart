import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_dark_scanner/data/settings.dart';

void main() {
  test('name matching defaults to the downloaded list and parses saved values', () {
    expect(NameMatching.parse(null), NameMatching.offlineList);
    expect(NameMatching.parse('online'), NameMatching.scryfallOnline);
    expect(NameMatching.parse('offline'), NameMatching.offlineList);
    expect(AppSettings().nameMatching, NameMatching.offlineList);
  });
}
