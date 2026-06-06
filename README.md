# OXO

A faithful recreation of Alexander Douglas's 1952 OXO — the first graphical video game, originally written for the EDSAC computer at Cambridge.

Rendered in Metal with a phosphor CRT dot-matrix display, scanlines, barrel distortion, and afterglow decay.

---

## Download

**[→ Download OXO.zip from Releases](https://github.com/Razormaron/OXOMetal/releases/latest)**

Unzip and double-click `OXO.app` to play. Requires macOS 13+ on Apple Silicon.

> If macOS blocks the app on first launch: right-click → Open → Open.

---

## How to play

- You are **O** (amber). EDSAC is **X** (blue-white).
- Click a cell, or use the numpad: **7 8 9 / 4 5 6 / 1 2 3**
- Press **Space** to start or restart a game.
- Score is shown in the title bar.

The AI plays a perfect minimax strategy — the same claim Douglas made about the original.

---

## Build from source

Requires Xcode command-line tools and an Apple Silicon Mac.

```bash
git clone https://github.com/Razormaron/OXOMetal.git
cd OXOMetal
bash install.sh        # builds OXO.app → /Applications
```

Or just run without installing:

```bash
swift run -c release
```

---

## About the original

OXO was written in 1952 by Alexander Douglas as part of his PhD thesis on human–computer interaction. It ran on the EDSAC at Cambridge and displayed on a 35×16 dot Williams tube oscilloscope. The human player used a rotary telephone dial to select cells.
