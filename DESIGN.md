# WOS Viewer — Score-utveckling

## Plan (skivor)

| Skiva | Innehåll | Status |
|-------|----------|--------|
| **1** | Drag/flytta, resize, inspector, spara | Pågår |
| **2** | Playhead + uppspelning av segment | Senare |
| **3** | Manuella time-fields & dynamic forms | Senare |
| **4** | Bättre auto-förslag + SVG/PDF-export | Senare |

Princip: en **testbar redigeringsloop** per skiva. Inte allt på en gång.

## Skiva 1 — mål

Analytikern ska kunna:
1. Markera ett auto-föreslaget objekt
2. Dra det i tid / mellan lanes
3. Ändra start/slut med handtag
4. Justera label, symbol, fylld/öppen, notering i inspector
5. Spara `.wosscore.json` och öppna igen

## Datamodell

Oförändrad kärna (`ScoreDocument` / `ScoreObject`). Se tidigare JSON-schema.

## Referenser

- Thoresen spectromorphology / Parmerud *Les objets obscurs* III  
- Chan Theme Fabric = separat spår, inte i skiva 1–3
