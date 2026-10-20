import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_dark_scanner/data/edhrec.dart';

void main() {
  test('slugs match EDHREC page names', () {
    expect(edhrecSlug("Atraxa, Praetors' Voice"), 'atraxa-praetors-voice');
    expect(edhrecSlug('Captain Howler, Sea Scourge'), 'captain-howler-sea-scourge');
    expect(edhrecSlug('Jodah, the Unifier'), 'jodah-the-unifier');
    expect(edhrecSlug('Esika, God of the Tree // The Prismatic Bridge'), 'esika-god-of-the-tree');
    expect(edhrecCommanderSlug(['Tymna the Weaver', 'Kraum, Ludevic\'s Opus']),
        'kraum-ludevics-opus-tymna-the-weaver');
  });

  test('parses sections, synergy and inclusion', () {
    final page = parseEdhrecPage({
      'header': 'Captain Howler, Sea Scourge (Commander)',
      'container': {
        'json_dict': {
          'cardlists': [
            {
              'header': 'High Synergy Cards',
              'tag': 'highsynergycards',
              'cardviews': [
                {'name': 'Brazen Borrower', 'synergy': 0.31, 'num_decks': 520, 'potential_decks': 1000},
                {'name': 'Faithless Looting', 'synergy': 0.4, 'inclusion': 400, 'potential_decks': 1000},
              ],
            },
            {'header': 'Empty', 'tag': 'empty', 'cardviews': []},
            {
              'header': 'Instants',
              'tag': 'instants',
              'cardviews': [
                {'name': 'Counterspell', 'synergy': -0.02, 'num_decks': 700, 'potential_decks': 1000},
              ],
            },
          ],
        },
      },
    });
    expect(page.sections.map((s) => s.title), ['High synergy', 'Instants']);
    final b = page.sections.first.cards.first;
    expect(b.inclusion, closeTo(0.52, 0.001));
    expect(b.caption, '52% of decks · +31% synergy');
    expect(page.sections.first.cards[1].inclusion, closeTo(0.4, 0.001));
    expect(page.sections[1].cards.single.caption, '70% of decks · -2% synergy');
  });
}
