# Dark Scanner — MTG card scanner that copes with black cards

A Flutter (Android-first) card scanner in the spirit of ManaBox, built around one problem: black-bordered and black-frame cards on dark playmats, which most scanners can't pick out.

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

## Features

- Live camera scanning with a card guide; the outline turns green once it locks onto real edges
- Torch toggle, glare and low-light hints
- Offline fuzzy name matching (Scryfall card-name catalogue, cached weekly)
- Exact-printing lookup by set code and collector number, plus a printing picker
- Foil toggle, auto-add mode for scanning a stack quickly
- Local collection with quantities and EUR/USD prices
- Export a **Moxfield-format CSV** (Collection → Import), which also works for most other sites

## Build and run (Windows)

You need **Flutter 3.44 or newer** (the camera plugin requires it), Android Studio or the Android SDK, and an Android phone with USB debugging on.

```powershell
cd mtg_dark_scanner
# Generate the Android scaffolding (gradle, MainActivity, icons).
# Existing files, including lib/ and the AndroidManifest.xml with the camera permission, are kept.
flutter create --org com.ollie --project-name mtg_dark_scanner --platforms android .
flutter pub get
flutter test                 # unit tests: edge refiner, OCR parsing, name matching, YUV rotation
flutter run --release        # with the phone plugged in
```

If `flutter create` reports that the minimum Android SDK is too low for ML Kit, set `minSdk = 21` (or higher) in `android/app/build.gradle.kts`.

First launch downloads the card-name list (about 1 MB) from Scryfall. After that, name matching works offline. The lookup itself still needs a connection.

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
    collection.dart         JSON-backed collection + Moxfield CSV export
  ui/                       scanner, overlay, collection screens
test/                       unit tests (synthetic black-card scenes etc.)
tool/                       Python mirror + photo harness + synthetic scene generator
```

## Known limitations / next steps

- Tested on synthetic scenes, not yet on real photos or a real device. Run `try_photo.py` on a few of your own dark cards first.
- The collector-line parser expects the M15-and-later layout. Older cards (pre-2015) match by name only, then you pick the printing.
- The title crop assumes a normal frame. Full-art, showcase and borderless cards with unusual title positions may need extra regions.
- English OCR only (ML Kit Latin script).
- Possible next steps: let the user flag mats where edges fail and store per-mat tuning; batch "sorting mode" by colour or set; price in GBP via a currency conversion.

## Getting an APK without installing Flutter (GitHub Actions)

1. Create a new GitHub repository (it can be private) and upload the contents of this folder, including the `.github` folder.
2. Open the repo's **Actions** tab. The **Build APK** workflow runs on every push, or you can start it with **Run workflow**.
3. When the run goes green (about 5–8 minutes), open it and download **dark-scanner-apk** from the Artifacts section.
4. Unzip it, copy `app-release.apk` to your phone and open it (allow "install unknown apps" for your file manager).

The release build is signed with Flutter's debug key, which is fine for sideloading and testing but not for the Play Store.
