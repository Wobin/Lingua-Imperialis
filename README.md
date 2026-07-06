# Lingua Imperialis

Offline, on-the-fly translation of incoming chat in Warhammer 40,000: Darktide.

When a teammate types in another language, Lingua Imperialis detects the language and
appends an English translation on a second line beneath their message. Everything runs
locally on your machine, offline, once the translation model is downloaded. No chat text
ever leaves your PC.

## How it works

- A self-contained native library (`bin/dtranslate.dll`) runs a neural machine-translation
  model (NLLB-200) plus a fastText language detector, entirely on the CPU, off the game
  thread so there is no stutter.
- The mod hooks the chat display and appends the translation in place.
- Client-side only. Nothing is required of the host or other players.

## First-run model download

The mod ships small. On first launch it downloads the ~600 MB translation model (int8)
from this repository's Releases into a local cache, shows progress in the mod console, and
enables translation once it is present. If the download fails, chat keeps working normally
and the console shows where to place the model manually.

## Test command

Type `/li_translate <text>` in the in-game chat box to translate any string yourself, for
example `/li_translate Hallo Welt`. It echoes the detected source language and the
translation, e.g. `[li] de -> "Hello world"`. Your own outgoing chat lines are intentionally
not auto-translated, so this command is the way to verify translation on your own.

## Credits

Translation model: NLLB-200 (Meta AI), CC-BY-NC. Language detection: fastText `lid.176`.
Inference: CTranslate2 + SentencePiece. Mod by Wobin.
