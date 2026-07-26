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

## Bygg & kör

```bash
cd /Users/wallofsoundab/Undervisning/WOSViewer
xcodegen generate
open WOSViewer.xcodeproj
```

I Xcode: scheme **WOSViewer** → Run (⌘R).

```bash
xcodegen generate
xcodebuild -scheme WOSViewer -configuration Debug -derivedDataPath ./DerivedData build
open "./DerivedData/Build/Products/Debug/WOS Viewer.app"
```

## Branding

- App-ikon: `icon.icns` (WallofSound)
- Logotyp: `WallofsoundAB_4500x1525.eps` → PNG i `Assets.xcassets/WOSLogo`
