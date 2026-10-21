# HEIF Thumbnail Proof of Concept

Native macOS replacement for Rapid Photo Downloader's Linux HEIF thumbnail
path (`raphodo/heif.py` + `pillow_heif`). Uses ImageIO only — no libheif,
no Pillow, no PyQt.

## Build

```sh
swiftc -O -o heifthumb heifthumb.swift
```

## Test with a HEIC file

```sh
./heifthumb "/Library/User Pictures/Flowers/Lotus.heic" /tmp/lotus.png 512
```

Expected: `wrote /tmp/lotus.png 512x512` plus source dimensions and EXIF date.

## Why this fixes the Linux problem

The Linux build depends on the optional `pillow_heif` package and on Pillow
being compiled against PyQt5. When either is missing, `have_heif_module` is
False and HEIF thumbnails are silently skipped. On macOS, ImageIO decodes
HEIF/HEIC out of the box, so the special case (`is_heif()`) and the
`load_heif` code path can be removed entirely; one code path handles every
image format.

For formats ImageIO cannot decode, fall back to `QLThumbnailGenerator`
(macOS 10.15+).
