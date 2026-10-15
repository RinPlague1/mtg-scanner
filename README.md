# MTG Binder (working title) — collection, decks, friends and trades

A Flutter (Android-first) MTG collection app in the spirit of ManaBox, with:

- **A scanner that copes with black cards** on dark playmats (details below).
- **Binders:** *Showcase* (not for trade; friends can see it, plus a public share link for flexing), *Up for trade* (offered first), and the default *Collection*.
- **Organising:** sort (date added, name, price, set, mana value, colour, rarity), filter (colour identity, type, rarity, condition, foil, tags), your own tags like "Aang staples" or "To sell", long-press multi-select for bulk moves / condition / tags / delete, and a list or card-image grid view.
- **Scan list:** scanned cards wait for review, so you can fix the printing, foil, condition and binder before adding them.
- **Imports:** TXT and CSV from ManaBox, Moxfield, Deckbox, Archidekt and Arena, or pasted lists.
- **Deck storage:** Built / Brewing / Retired decks. Missing cards become trade wants automatically; Built decks keep their cards out of trades ("the deck takes priority").
- **Friends and trade suggestions:** add friends by username, see their Showcase, Up for trade binder and wants, and get two-way trade suggestions ranked by deck gaps. Propose, counter, accept, and mark trades as swapped; both collections update when both of you confirm.
- **Offline-first:** everything works offline and syncs to Supabase when you're online.
- **Prices in GBP:** Cardmarket EUR prices (via Scryfall) converted with the daily ECB rate.

The app name lives in `lib/config.dart` (`AppConfig.appName`) and `android:label` in `android/app/src/main/AndroidManifest.xml`.

## Online setup (friends, trades, sync)

Without this the app still builds and works fully offline; the Friends and Trades tabs explain what's missing.

1. Create a free project at [supabase.com](https://supabase.com).
2. Open **SQL Editor → New query**, paste all of `supabase/schema.sql`, and click **Run**. It's safe to run again after updates.
3. **Authentication → Sign In / Providers → Email** should be on. For testing, you can turn off **Confirm email** so new accounts can sign in straight away.
4. **Project Settings → API**: copy the **Project URL** and the **anon public** key.
5. In this GitHub repo: **Settings → Secrets and variables → Actions → New repository secret**, add `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
6. Push, or run the **Build APK** workflow. The APK it produces has online features switched on.

The anon key is designed to be public; Row Level Security in `schema.sql` decides who can see what. Friends see only your Showcase, Up for trade binder, spares and wants. Decks, the rest of your collection and your wishlist stay private.

### Showcase share links (optional)

`web_showcase/index.html` is a single static page that shows someone's Showcase from a link. Host it anywhere static (Netlify Drop, Cloudflare Pages, or GitHub Pages on a public repo), then add its URL as a third secret, `SHOWCASE_URL`. "Share Showcase" then sends a link anyone can open. Without it, the app shares a text list instead. "Reset Showcase share link" on the Friends tab makes old links stop working.

### Running locally

```powershell
flutter run --release --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJ... --dart-define=SHOWCASE_URL=https://your-host/index.html
```

## How trade suggestions work

- **Spares** = everything in Up for trade, plus Collection copies that no Built deck needs. Built decks take copies from Collection first, then Showcase, then Up for trade. Showcase cards are never offered. Cards promised in open trades are held back.
- **Wants** = cards missing from Built decks (priority 3) and Brewing decks or your wishlist (priority 2). Retired decks add nothing and release their cards as spares.
- Each friend gets a score: 3 per card that fills a Built-deck gap, 2 for Brewing/wishlist, +1 if it's from their Up for trade binder, +5 if both sides get something. Cards match on name, so any printing fills a deck slot.
- This runs on the phone (`lib/data/trade_logic.dart`, unit-tested); each phone publishes its spares and wants for friends.

## Why black cards fail elsewhere, and what this does differently

Typical scanners run a Canny edge detector on a grayscale frame and look for the biggest four-sided contour. A black border (about 15/255) on a dark mat (about 25/255) is only a few grey levels apart. That's below any usable Canny threshold, so the contour never closes and the scan never fires. On the synthetic test scenes in `tool/`, a standard OpenCV Canny + contour detector failed on **every** black-bordered case and only worked on the white-bordered one.

The pipeline here (`lib/vision/`):

| Problem | Fix |
|---|---|
| Black border on a dark mat has almost no brightness difference | Edges are measured in **log intensity per colour channel**. 15→25 is the same ratio as 150→250, so the edge is as strong as a white border on a table. Taking the max over R, G and B also catches mats that differ in hue (navy, green). |
| Weak edges get lost in noise and cloth texture | No closed contour needed. The on-screen guide gives each side's rough position, so each side is a 1-D straight-line search that **averages about 200 pixels along the line**, which pulls faint edges well clear of noise. |
| Strong inner frame or art-box edges get mistaken for the card edge | The refiner takes the **outermost** significant edge, judged against the mat just outside it. It fits **one rotation for all four sides**, so a slanted line can't latch onto an inner edge. |
| Log space amplifies sensor noise in near-black areas | Significance is measured against local noise on the mat side, not a global floor. |
| Border is literally the same colour as the mat | Falls back to the inner border edge or the guide. The title and collector-line crops are padded to cover either case. The set line is printed *on* the black border, so that crop extends past the card edge. |
| Glare or foil hotspot over the title | Glare is measured on the title crop (bright, colourless pixels). If there's glare, the crop is flat-field corrected before OCR, and the app tells you to tilt the card or switch the torch off. |
| White text on black (collector line, some frames) | Each crop is contrast-stretched and auto-inverted to dark-on-light before OCR. |
| One bad OCR read | A card is accepted only when **2 of the last 4 frames agree**, after offline fuzzy matching against every card name. |

The exact printing comes from reading the **set code and collector number** (`DMU • EN`, `0107 M`) and calling `GET /cards/{set}/{number}` on Scryfall. If that line is unreadable, it falls back to the name, and you can choose the printing yourself.

Synthetic results (1080×1920 frames, Dart-style sampling):

| Scene | Canny baseline | This refiner |
|---|---|---|
| Black border, dark mat | not found | 1.5 px corner error |
| Shifted + rotated 3° | not found | 1.4 px |
| Big offset, rotated −4° | not found | 2.0 px |
| Glare over title | not found | 4.7 px |
| Noisy low light | not found | 1.9 px |
| White border (control) | 1.6 px | 2.2 px |

## Scanner features

- Live camera scanning with a card guide; the outline turns green once it locks onto real edges
- Torch toggle, glare and low-light hints
- Name matching your way (gear icon on the Scan tab): download Scryfall's card-name list once (about 1 MB, cached weekly) for fast offline matching, or **use Scryfall online** so nothing is downloaded and each scan's text goes to Scryfall's fuzzy search
- Exact-printing lookup by set code and collector number, plus a printing picker
- Foil toggle, auto-add mode for scanning a stack quickly
- Choose the binder scanned cards go into
- Export a **Moxfield-format CSV** (Collection → Import), which also works for most other sites

## Build and run (Windows)

You need **Flutter 3.44 or newer** (the camera plugin requires it), Android Studio or the Android SDK, and an Android phone with USB debugging on.

```powershell
cd mtg-scanner
# Generate the Android scaffolding (gradle, MainActivity, icons).
# Existing files, including lib/ and the AndroidManifest.xml with the camera permission, are kept.
flutter create --org com.ollie --project-name mtg_dark_scanner --platforms android .
flutter pub get
flutter test                 # unit tests: edge refiner, OCR parsing, name matching, YUV rotation
flutter run --release        # with the phone plugged in
```

If `flutter create` reports that the minimum Android SDK is too low for ML Kit, set `minSdk = 21` (or higher) in `android/app/build.gradle.kts`.

By default, first launch downloads the card-name list (about 1 MB) from Scryfall, and name matching then works offline. To skip the download, tap the gear on the Scan tab and choose **Use Scryfall online**. The printing and price lookup always needs a connection.

## Tuning with your own photos (no phone build needed)

`tool/refine_mirror.py` is a line-for-line Python mirror of `lib/vision/edge_refiner.dart`:

```powershell
pip install numpy opencv-python
python tool/try_photo.py my_black_card.jpg
```

This writes `my_black_card_debug.png` showing the guide, the detected card and the two OCR crops. Shoot portrait photos with the card filling about 78% of the width, the way the app's guide asks. If a mat gives you trouble, change `band` or `min_contrast` in the Python mirror, then copy the same values into `EdgeRefiner`.

## Project layout

```
lib/
  main.dart                 app entry
  config.dart               app name, Supabase settings (from --dart-define)
  services.dart             creates the stores and services
  scan_controller.dart      camera stream → isolate analysis → ML Kit OCR → voting → Scryfall
  vision/
    geometry.dart           guide box, card regions (title / collector line), quad maths
    frame.dart              YUV420/NV21 sampling with sensor rotation, region warping, glare stat
    edge_refiner.dart       the dark-card edge finder
    scan_pipeline.dart      per-frame pipeline run in a background isolate, OCR crop enhancement
  ocr/card_text_parser.dart title cleanup, set code + collector number parsing
  data/
    name_index.dart         offline fuzzy name matcher (bounded Levenshtein + prefix)
    scryfall.dart           API client (rate-limited, proper User-Agent)
    collection.dart         JSON-backed collection with binders + Moxfield CSV export
    decks.dart, wishlist.dart
    list_parser.dart        TXT / CSV import parsing
    importer.dart           Scryfall bulk lookup for imports
    trade_logic.dart        spares, wants, trade suggestions (pure, unit-tested)
    prices.dart             EUR → GBP
  social/
    backend.dart            Supabase calls
    social_store.dart       friends, trades, suggestions (cached for offline)
    sync.dart               offline-first sync to Supabase
  ui/                       five tabs: Scan, Collection, Decks, Friends, Trades
supabase/schema.sql         tables, Row Level Security, functions
web_showcase/index.html     public Showcase viewer for share links
test/                       unit tests (synthetic black-card scenes etc.)
tool/                       Python mirror + photo harness + synthetic scene generator
```

## Known limitations / next steps

- Tested on synthetic scenes, not yet on real photos or a real device. Run `try_photo.py` on a few of your own dark cards first.
- The collector-line parser expects the M15-and-later layout. Older cards (pre-2015) match by name only, then you pick the printing.
- The title crop assumes a normal frame. Full-art, showcase and borderless cards with unusual title positions may need extra regions.
- English OCR only (ML Kit Latin script).
- Imports need a "Name" column for CSVs; there is no manual column-mapping screen yet.
- Sign-in is email + password; Google sign-in and in-app chat are later items.
- Sync is "phone wins": the last phone to sync replaces the server copy, so using two phones at once can overwrite changes.
- Possible next steps: per-mat tuning; batch "sorting mode"; price history; playgroups; QR-code friend adds.

## Getting an APK without installing Flutter (GitHub Actions)

1. Create a new GitHub repository (it can be private) and upload the contents of this folder, including the `.github` folder.
2. Open the repo's **Actions** tab. The **Build APK** workflow runs on every push, or you can start it with **Run workflow**.
3. When the run goes green (about 5–8 minutes), open it and download **mtg-binder-apk** from the Artifacts section.
4. Unzip it, copy `app-release.apk` to your phone and open it (allow "install unknown apps" for your file manager).

The release build is signed with Flutter's debug key, which is fine for sideloading and testing but not for the Play Store.
