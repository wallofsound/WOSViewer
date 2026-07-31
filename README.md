# WOS Viewer

**WOS** = WallofSound. Fristående macOS-app från WallofSound AB för feature-plottar och spektromorfologisk **score**-analys från ljudfiler (inspirerad av SEMA + Thoresen/Parmerud).

## Funktioner

- Öppna **wav / mp3 / m4a** (eller AIFF / CSV)
- **Features:** RMS, Novelty, Spectral Centroid, ZCR, MFCC₁
- **Score:** auto-segmentering → föreslagna ljudobjekt, time-fields, dynamic forms, brackets
- **Score-redigering:** Edit / Viewer / **Eyes** (lyssnarläge med förväntan kring playhead)
- **Export** av score: PNG / PDF / SVG (Viewer-stil)
- **Uppspelning** med playhead + scrub + spela markerat segment
- Symbolpalett (Thoresen-inspirerad, förenklad) + manuell placering
- Pitch bars + harmonic coloring; spektrogram-underlag
- Sparar `*.wos.csv` och `*.wosscore.json` bredvid källfilen
- WallofSound-ikon + logotyp

Se `DESIGN.md` för plan och datamodell.

## Krav

- macOS 14+
- Xcode 15+

## Klona & kör

```bash
git clone git@github.com:wallofsound/WOSViewer.git
cd WOSViewer
open WOSViewer.xcodeproj
```

I Xcode: scheme **WOSViewer** → Run (⌘R).

### Alternativ: generera projekt med XcodeGen

```bash
xcodegen generate
open WOSViewer.xcodeproj
```

### Bygg från terminal

```bash
xcodebuild -scheme WOSViewer -configuration Release -derivedDataPath ./DerivedData build
open "./DerivedData/Build/Products/Release/WOS Viewer.app"
```

## Branding

- App-ikon: `icon.icns` (WallofSound)
- Logotyp: `WallofsoundAB_4500x1525.eps` → PNG i `Assets.xcassets/WOSLogo`
