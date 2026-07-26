# WOS Viewer

**WOS** = WallofSound. Fristående macOS-app från WallofSound AB för feature-plottar från ljudfiler (inspirerad av SEMA).

## Funktioner

- Öppna **wav / mp3 / m4a** (eller AIFF)
- Extraherar:
  - RMS Energy
  - Novelty (spectral flux)
  - Spectral Centroid
  - Zero-Crossing Rate
- Visar fyra paneler i SEMA-stil
- Sparar automatiskt en CSV (`*.wos.csv`) bredvid ljudfilen
- Kan öppna befintlig SEMA-/WOS-CSV och bara plotta
- WallofSound-ikon + logotyp

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
