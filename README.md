# MHI-Berry – MP3-Decoder für AmiAMP auf PiStorm/Emu68

Autor: MichiB210 (mit Hilfe von KI)

**MHI-Berry** ist ein MHI-Treiber (`mhiberry.library`), der MP3-Dateien auf dem
PiStorm/Raspberry Pi decodiert und den Ton direkt über dessen **HDMI-Ausgang** ausgibt.

Die Idee dahinter: AmiAMP decodiert die MP3-Datei nicht auf der Amiga-Seite. Stattdessen
wird der komprimierte MP3-Datenstrom über MHI an den PiStorm weitergegeben. Die eigentliche
Decodierung übernimmt dort **Helix MP3 auf dem Raspberry Pi** (auf dessen zweitem
CPU-Kern, CPU1). Das erzeugte PCM-Audio geht anschließend direkt an den HDMI-Ausgang.

    AmiAMP → MHI (MPEG Hardware Interface) → PiStorm / Raspberry Pi (CPU1) → Helix MP3 → PCM → HDMI

Es gibt bereits HDMI-Audio-Lösungen für Emu68 über AHI. MHI-Berry geht einen anderen Weg:
Es nutzt die **MHI-Schnittstelle von AmiAMP** und lagert zusätzlich die MP3-Decodierung
auf den Raspberry Pi aus. Der 68k bleibt dadurch frei.

## Was funktioniert

- MP3-Wiedergabe (MPEG Layer III, Stereo, CBR und VBR)
- Pause / Play
- Stop
- Vorspulen / Seek
- Titelwechsel
- Lautstärkeregelung über AmiAMP
- automatischer Start der Decoder-Engine im Hintergrund

Man muss keinen zusätzlichen Player starten und keine Engine von Hand aufrufen. AmiAMP wird
ganz normal gestartet und verwendet den MHI-Treiber. Die Decoder-Engine startet beim ersten
Zugriff automatisch und bleibt danach still im Hintergrund bereit, auch wenn AmiAMP beendet
und neu gestartet wird.

Noch nicht freigegeben: Mono-MP3s.

## Getestet

**Amiga 2000**, 1 MB Chip-RAM, **PiStorm Classic mit Raspberry Pi 3A+**

- Emu68 1.0.7 mit Caffeine / AmigaOS 3.9
- Emu68 1.1.0-beta.1 mit AmigaOS 3.2.3

## Download

Fertiges Paket: siehe **[Releases](https://github.com/MichiB210/MHI-Berry/releases)**,
oder die Dateien direkt aus dem Ordner [`release/`](release/).

## Installation

### 1. Gepatchten Kernel einsetzen

MHI-Berry braucht einen gepatchten Emu68-Kernel („BerryCore“), der den zweiten CPU-Kern des
Pi für den Decoder bereitstellt. Bitte den passenden zu deiner Emu68-Version nehmen:

| Emu68-Version | Kernel-Datei | Meldung beim Booten |
|---|---|---|
| 1.0.7 | `kernel/Emu68-pistorm-BerryCore` | `Emu68-BerryCore 1.0.7 (13.09.2026)` |
| 1.1.0-beta.1 (PiStorm classic) | `kernel/Emu68-pistorm-classic-BerryCore2.gz` | `Emu68-BerryCore2 1.1.0-beta.1 (26.10.2026)` |

Dafür gibt es zwei Möglichkeiten:

1. Den bisherigen Kernel zur Sicherheit umbenennen und den neuen unter dem alten Namen an
   dessen Stelle kopieren.
2. Oder in der `config.txt` den `kernel=`-Eintrag auf den neuen Dateinamen ändern, z. B.

       kernel=Emu68-pistorm-classic-BerryCore2.gz

   bzw., falls der Kernel im Unterordner `kernel` liegt:

       kernel=kernel/Emu68-pistorm-classic-BerryCore2.gz

Beim nächsten Neustart erscheint die BerryCore-Meldung aus der Tabelle:

![Bootschirm mit Emu68-BerryCore](https://filedn.eu/l9KjryqP6muhkPuoaMYzK1L/amiga/mp3/boot.png)

### 2. MHI-Dateien installieren

- `C/mhiberry_engine` → `C:`
- `LIBS/MHI/mhiberry.library` → `LIBS:MHI/`
- `LIBS/MHI/berry_mp3.module` → `LIBS:MHI/`

`berry_mp3.module` enthält den Helix-MP3-Decoder, der auf dem Raspberry Pi läuft.
`mhiberry_engine` **nicht** von Hand starten, die Library startet sie automatisch.

### 3. AmiAMP einstellen

**Einstellungen → Dekoder**

- **MHI Unterstützung:** aktivieren
- **MHI Treiber:** `mhiberry.library`

![AmiAMP-Einstellungen: Dekoder mit MHI-Treiber mhiberry.library](https://filedn.eu/l9KjryqP6muhkPuoaMYzK1L/amiga/mp3/AMIAMP.png)

Neustart. Das war's. Viel Spaß!

Wer seine MP3s vom USB-Stick abspielen möchte, kann zusätzlich meinen USB-Treiber für
Poseidon verwenden: [berryPi3Ap.device](https://github.com/MichiB210/berryPi3Ap.device)

## Inhalt dieses Repos

| Ordner | Was |
|---|---|
| `amiga/` | 68k-Assembler-Quellen: `mhiberry.library.s`, `mhiberry_engine.s` (+ `vpv18_test.aac`, wird per `incbin` eingebunden) |
| `module/` | Quellen des CPU1-Moduls `berry_mp3.module` + Helix-Decoder (chmorgan/libhelix-mp3, unverändert) mit Lizenzen |
| `kernel/emu68_1.0.7/` | BerryCore-Patch für Emu68 1.0.7 (PiStorm) |
| `kernel/emu68_1.1.0-beta.1/` | BerryCore2-Patch für Emu68 1.1.0-beta.1 (PiStorm classic) |
| `release/` | Die fertigen, auf Hardware getesteten Dateien |
| `build_all.sh` | Baut alles aus den Quellen und vergleicht mit `release/` |

## Bauen

    sh build_all.sh            (vasm per VASM=/pfad/vasmm68k_mot angeben)

Benötigt: vasm (`vasmm68k_mot`), clang, ld.lld, llvm-objcopy, python3, unzip, gzip.

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
