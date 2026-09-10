# Test fixtures

Small real-world audio files used by `AudioPipelineTests`. Everything else
the integration tests need is synthesised at run time (see
`AudioFixtures.swift`); these exist because the bundled ffmpeg can decode
MP3 but not encode it, so a genuine MP3 has to be checked in.

## mp3/

Three 2-second mono sine tones, CBR 64 kbps, with ID3v2 tags, made with
LAME 4.0 (`brew install lame`):

| file           | tone    | ID3 title     | artist         | album        | track |
|----------------|---------|---------------|----------------|--------------|-------|
| chapter1.mp3   | 300 Hz  | Chapter One   | Fixture Author | Fixture Book | 1/3   |
| chapter2.mp3   | 600 Hz  | Chapter Two   | Fixture Author | Fixture Book | 2/3   |
| chapter3.mp3   | 1200 Hz | Chapter Three | Fixture Author | Fixture Book | 3/3   |

Regenerate (from 16-bit 44.1 kHz mono WAVs at amplitude 12000/32767):

```sh
lame --quiet -b 64 --cbr -m m --tt "Chapter One" --ta "Fixture Author" \
     --tl "Fixture Book" --tn 1/3 --tg Audiobook --add-id3v2 tone300.wav chapter1.mp3
```

The tests assert the tone frequency and tag values above, so keep the
table and the files in sync.
