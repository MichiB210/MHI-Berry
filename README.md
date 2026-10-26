# mhiberry – MHI-MP3-Decoder für AmiAMP auf PiStorm/Emu68

Autor: MichiB210 (mit Hilfe von KI)

Pfad: **AmiAMP → MHI → mhiberry.library → mhiberry_engine → Emu68-BerryCore (CPU1) →
berry_mp3.module (Helix MP3) → PCM16 → VideoCore ril.audio_render → HDMI**

Getestet: Amiga 2000, PiStorm Classic, Raspberry Pi 3A+, Emu68 1.0.7 BerryCore und
Emu68 1.1.0-beta.1 BerryCore2.

## Inhalt

| Ordner | Was |
|---|---|
| `amiga/` | 68k-Assembler-Quellen: `mhiberry.library.s`, `mhiberry_engine.s` (+ `vpv18_test.aac`, wird per `incbin` eingebunden) |
| `module/` | Quellen des CPU1-Moduls `berry_mp3.module` + Helix-Decoder (chmorgan/libhelix-mp3, unverändert) mit Lizenzen |
| `kernel/emu68_1.0.7/` | BerryCore-Patch für Emu68 1.0.7 (PiStorm) |
| `kernel/emu68_1.1.0-beta.1/` | BerryCore2-Patch für Emu68 1.1.0-beta.1 (PiStorm classic) |
| `release/` | Die fertigen, auf Hardware getesteten Dateien |
| `build_all.sh` | Baut alles aus den Quellen und vergleicht mit `release/` |

## Installation (release/)

1. Kernel auf die SD-Karte, in `config.txt` `kernel=` darauf setzen:
   - Emu68 1.0.7: `Emu68-pistorm-BerryCore`
   - Emu68 1.1.0-beta.1: `Emu68-pistorm-classic-BerryCore2.gz`
2. `C/mhiberry_engine` → `C:`
3. `LIBS/MHI/mhiberry.library` und `LIBS/MHI/berry_mp3.module` → `LIBS:MHI/`
4. AmiAMP: Einstellungen → Dekoder → MHI-Unterstützung an, Treiber `mhiberry.library`.

`mhiberry_engine` nicht von Hand starten, die Library startet sie automatisch.

## Bauen

    sh build_all.sh            (vasm per VASM=/pfad/vasmm68k_mot angeben)

Stand des Nachbaus:

| Datei | Werkzeug | Ergebnis |
|---|---|---|
| mhiberry.library | vasm `-m68020 -Fhunkexe -nosym` | byte-identisch |
| mhiberry_engine | vasm `-m68020 -Fhunkexe -nosym` | byte-identisch |
| berry_mp3.module | clang `-O2 -mcpu=cortex-a53`, ld.lld | funktional gleich; byte-identisch nur mit dem Original-Compiler (clang 17 aus der Swift-Toolchain) |
| Emu68-pistorm-BerryCore | build_berrycore.py | byte-identisch |
| Emu68-pistorm-classic-BerryCore2.gz | build_berrycore_110b1.py | byte-identisch |

`berry_mp3.module` = Rohmodul `berry_mp301.module` + API-1.0-/`$VER`-Angaben in den
Header-Bytes `$10–$3F`. Die Engine prüft diese Angaben und löscht sie vor dem Laden
auf CPU1 wieder.

## Lizenzen

- Emu68 © Michal Schulz, MPL-2.0. Die Kernel-Patches sind ebenfalls MPL-2.0.
- Helix MP3 Decoder © RealNetworks, RPSL/RCSL (siehe `module/third_party/`).
- Eigene Teile (`amiga/`, `module/src/`, `module/inc/`, `build_all.sh`): MIT, siehe `LICENSE`.
