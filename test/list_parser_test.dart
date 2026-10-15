import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_dark_scanner/data/importer.dart';
import 'package:mtg_dark_scanner/data/list_parser.dart';
import 'package:mtg_dark_scanner/data/models.dart';

void main() {
  group('TXT lists', () {
    test('plain, x-quantity, set/number, foil and sections', () {
      const text = '''
Commander
1 Avatar Aang

Deck
1 Sol Ring
1x Arcane Signet (C21) 263
4 Island *F*
Fire // Ice
// a comment

SIDEBOARD:
2 Negate
''';
      final p = parseCardList(text);
      expect(p.wasCsv, isFalse);
      expect(p.problems, isEmpty);
      expect(p.lines.map((l) => l.name), ['Avatar Aang', 'Sol Ring', 'Arcane Signet', 'Island', 'Fire // Ice', 'Negate']);
      expect(p.lines[0].commander, isTrue);
      expect(p.lines[2].setCode, 'c21');
      expect(p.lines[2].collectorNumber, '263');
      expect(p.lines[3].qty, 4);
      expect(p.lines[3].foil, isTrue);
      expect(p.lines[4].qty, 1);
      expect(p.lines[5].section, 'sideboard');
      expect(p.cardCount, 10);
    });

    test('Archidekt commander tags and names with brackets', () {
      final p = parseTxt('1x Tam, Mindful First-Year (DSK) 1 [Commander{top}]\n1x Counterspell [Interaction]\n');
      expect(p.lines.first.name, 'Tam, Mindful First-Year');
      expect(p.lines.first.commander, isTrue);
      expect(p.lines.first.setCode, 'dsk');
      expect(p.lines[1].name, 'Counterspell');
      expect(p.lines[1].commander, isFalse);
    });

    test('deck from lines merges duplicates and drops the sideboard', () {
      final p = parseTxt('Commander\n1 Captain Howler, Sea Scourge\nDeck\n1 Sol Ring\n1 Sol Ring\nSideboard\n1 Negate\n');
      final deck = deckFromLines('Sharks', p.lines, DeckStatus.brewing);
      expect(deck.cards.first.name, 'Captain Howler, Sea Scourge');
      expect(deck.cards.first.commander, isTrue);
      expect(deck.needs['sol ring'], 2);
      expect(deck.needs.containsKey('negate'), isFalse);
      expect(deck.status, DeckStatus.brewing);
    });
  });

  group('CSV', () {
    test('ManaBox export', () {
      const csv = 'Name,Set code,Set name,Collector number,Foil,Rarity,Quantity,ManaBox ID,Scryfall ID,'
          'Purchase price,Misprint,Altered,Condition,Language,Purchase price currency\n'
          '"Sheoldred, the Apocalypse",dmu,Dominaria United,107,foil,mythic,2,1,abc-123,60,false,false,'
          'near_mint,en,EUR\n'
          'Sol Ring,c21,Commander 2021,263,normal,uncommon,1,2,def-456,1,false,false,lightly_played,en,EUR\n';
      final p = parseCardList(csv, fileName: 'ManaBox_Collection.csv');
      expect(p.wasCsv, isTrue);
      expect(p.problems, isEmpty);
      expect(p.lines.length, 2);
      expect(p.lines[0].name, 'Sheoldred, the Apocalypse');
      expect(p.lines[0].qty, 2);
      expect(p.lines[0].foil, isTrue);
      expect(p.lines[0].setCode, 'dmu');
      expect(p.lines[0].collectorNumber, '107');
      expect(p.lines[0].scryfallId, 'abc-123');
      expect(p.lines[1].foil, isFalse);
      expect(p.lines[1].condition, CardCondition.lp);
    });

    test('Moxfield export (also detected without a .csv name)', () {
      const csv = '"Count","Tradelist Count","Name","Edition","Condition","Language","Foil","Tags",'
          '"Last Modified","Collector Number","Alter","Proxy","Purchase Price"\n'
          '"3","0","Lightning Bolt","2xm","Near Mint","English","","","2024-01-01","117","False","False",""\n';
      final p = parseCardList(csv);
      expect(p.wasCsv, isTrue);
      expect(p.lines.single.qty, 3);
      expect(p.lines.single.setCode, '2xm');
      expect(p.lines.single.collectorNumber, '117');
    });

    test('Deckbox full edition names are ignored as set codes', () {
      const csv = 'Count,Tradelist Count,Name,Edition,Card Number,Condition,Language,Foil\n'
          '1,0,Counterspell,Dominaria United,48,Near Mint,English,\n';
      final p = parseCsv(csv);
      expect(p.lines.single.setCode, isNull);
      expect(p.lines.single.collectorNumber, '48');
    });

    test('missing Name column is reported', () {
      final p = parseCsv('foo,bar\n1,2\n');
      expect(p.lines, isEmpty);
      expect(p.problems.single, contains('Name'));
    });

    test('quoted commas and escaped quotes', () {
      expect(splitCsvLine('1,"Borrowing 100,000 Arrows","He said ""hi"""'),
          ['1', 'Borrowing 100,000 Arrows', 'He said "hi"']);
    });
  });

  test('name keys match across printings and faces', () {
    expect(nameKey('Delver of Secrets // Insectile Aberration'), 'delver of secrets');
    expect(nameKey('  Sol   Ring '), 'sol ring');
    expect(nameKey('Lim-Dûl the Necromancer'), 'lim-dul the necromancer');
  });
}
