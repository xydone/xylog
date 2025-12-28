# xylog

xylog is a lightweight media server for comics, mangas and eBooks.

> [!IMPORTANT]
> xylog is currently pre 1.0. Breaking changes may be made at any time.

## Features

- OPDS v1.2, with the ability of downloading many chapters at once
- KOReader Sync

## Usage

Once you have an [executable](#building), fill in the correct information inside `config/config.zon` and run!

## Building

*Prerequisites: you must have `Zig 0.15.2` installed.*

```
zig build -Doptimize=ReleaseSafe
```
