import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_dark_scanner/data/name_index.dart';
import 'package:mtg_dark_scanner/ocr/card_text_parser.dart';

void main() {
  group('set line', () {
    test('2022+ frame', () {
      final s = CardTextParser.setInfo(['0107 M', 'DMU • EN  Chris Rahn']);
      expect(s, const SetInfo('dmu', '107'));
    });
    test('M15-2021 frame with total', () {
      final s = CardTextParser.setInfo(['107/281 R', 'M20 · EN']);
      expect(s, const SetInfo('m20', '107'));
    });
    test('OCR confusions O->0 and missing bullet', () {
      final s = CardTextParser.setInfo(['O2I5 U', 'MKM EN']);
      expect(s, const SetInfo('mkm', '215'));
    });
    test('2023+ frame with the rarity first', () {
      expect(CardTextParser.setInfo(['R 0194', 'DFT EN MiRo fALONI']), const SetInfo('dft', '194'));
      expect(CardTextParser.setInfo(['R0194', 'DFT ·EN MiRNO FAILONI']), const SetInfo('dft', '194'));
      expect(CardTextParser.setInfo(['M 0012/0281', 'MKM • EN']), const SetInfo('mkm', '12'));
    });
    test('garbage gives null', () {
      expect(CardTextParser.setInfo(['~~', 'zz']), isNull);
    });
  });

  group('title cleaning', () {
    test('strips leaked mana cost', () {
      expect(CardTextParser.cleanName('Sheoldred, the Apocalypse 2 B B'), 'Sheoldred, the Apocalypse');
    });
    test('keeps apostrophes', () {
      expect(CardTextParser.cleanName('Urza’s Saga'), "Urza's Saga");
    });
  });

  group('name index', () {
    final idx = NameIndex([
      'Sheoldred, the Apocalypse',
      'Sheoldred, Whispering One',
      'Swamp',
      'Bloodtithe Harvester',
      'Fable of the Mirror-Breaker // Reflection of Kiki-Jiki',
      'Lim-Dûl the Necromancer',
    ]);
    test('exact', () => expect(idx.match('Swamp')?.name, 'Swamp'));
    test('OCR typos', () => expect(idx.match('Sheo1dred, the Apocalypes')?.name, 'Sheoldred, the Apocalypse'));
    test('truncated title', () => expect(idx.match('Bloodtithe Harv')?.name, 'Bloodtithe Harvester'));
    test('DFC front face', () => expect(idx.match('Fable of the Mirror-Breaker')?.name,
        'Fable of the Mirror-Breaker // Reflection of Kiki-Jiki'));
    test('accents folded', () => expect(idx.match('Lim-Dul the Necromancer')?.name, 'Lim-Dûl the Necromancer'));
    test('rejects noise', () => expect(idx.match('xqzv kkrp'), isNull));
  });
}
