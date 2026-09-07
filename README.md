# cliamp-plugin-red-sector



https://github.com/user-attachments/assets/9f628a6f-8a6a-4c19-814d-8aa9c44005e9



A wireframe equalizer for [cliamp](https://cliamp.stream), after the vector part of the Red Sector Inc. RSI Megademo (Amiga, 1989). Five hollow bars stand on a common ground line and tumble in front of a turning curve of points, each one driven by two spectrum bands. One inclined plane cuts each bar's top, so a bar ends in a slanted face rather than a flat lid. The curve walks a list of figures, after the point effects the demo cycles through: a tight spiral, three arms winding out of the centre, curled arms, rounded lobes and a three-petal rosette. It holds each one for a while, then eases across to the next, turning behind the bars and centred on the picture. Hidden edges are removed per bar, so a bar shows its front, one flank and its slanted top, the way the original vector objects do. Sibling of [led-burst](https://github.com/AlexZeitler/cliamp-plugin-led-burst), [block-burst](https://github.com/AlexZeitler/cliamp-plugin-block-burst), [vu-meter](https://github.com/AlexZeitler/cliamp-plugin-vu-meter), [reverb](https://github.com/AlexZeitler/cliamp-plugin-reverb), and [sine-rainbow](https://github.com/AlexZeitler/cliamp-plugin-sine-rainbow).

## Install

```sh
cliamp plugins install AlexZeitler/cliamp-plugin-red-sector
```

Then start cliamp and press `v` to cycle visualizers until `red-sector` appears.

cliamp asks you to approve the plugin's contents while installing. Editing the file later changes its hash and disables the plugin until you approve it again:

```sh
cliamp plugins trust red-sector
```

To pin a specific version:

```sh
cliamp plugins install AlexZeitler/cliamp-plugin-red-sector@v0.1.0
```

Remove with:

```sh
cliamp plugins remove red-sector
```

## Requirements

- cliamp with Lua plugin support
- A terminal with Braille (U+2800..U+28FF) and 16-color ANSI support - every modern terminal qualifies

## Related plugins

- [AlexZeitler/cliamp-plugin-led-burst](https://github.com/AlexZeitler/cliamp-plugin-led-burst) - Stereo LED matrix bursting outward from a center divider.
- [AlexZeitler/cliamp-plugin-block-burst](https://github.com/AlexZeitler/cliamp-plugin-block-burst) - Nested LED pyramid where each tier responds to a different frequency range.
- [AlexZeitler/cliamp-plugin-vu-meter](https://github.com/AlexZeitler/cliamp-plugin-vu-meter) - Ten analog-needle VU meters drawn with sub-pixel Braille.
- [AlexZeitler/cliamp-plugin-reverb](https://github.com/AlexZeitler/cliamp-plugin-reverb) - Horizontal LED matrix inspired by vintage HiFi reverberation displays.
- [AlexZeitler/cliamp-plugin-sine-rainbow](https://github.com/AlexZeitler/cliamp-plugin-sine-rainbow) - Ten overlapping sine curves, one per spectrum band, each in its own ANSI color.

## License

MIT - see [LICENSE](LICENSE).
