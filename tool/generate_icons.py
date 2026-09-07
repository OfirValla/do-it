"""Renders assets/icon/*.svg with headless Chrome and writes every Android
launcher asset (legacy mipmaps, adaptive foreground/background/monochrome
layers and the adaptive-icon XML).

Usage:  python tool/generate_icons.py [--no-render]
Needs:  Google Chrome, Python 3, Pillow (pip install pillow)
"""
import os
import shutil
import subprocess
import sys
import tempfile

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_DIR = os.path.join(ROOT, "assets", "icon")
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")
CHROME_CANDIDATES = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    "/usr/bin/google-chrome",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
]
SOURCES = ["icon_full", "icon_foreground", "icon_background", "icon_monochrome"]
# density -> (legacy 48dp icon px, adaptive 108dp layer px)
DENSITIES = {
    "mdpi": (48, 108),
    "hdpi": (72, 162),
    "xhdpi": (96, 216),
    "xxhdpi": (144, 324),
    "xxxhdpi": (192, 432),
}


def render():
    chrome = next((c for c in CHROME_CANDIDATES if os.path.exists(c)), None)
    if chrome is None:
        sys.exit("Chrome not found; run with --no-render to reuse the existing PNGs")
    profile = tempfile.mkdtemp(prefix="doit-chrome-")
    try:
        for name in SOURCES:
            svg = os.path.join(ICON_DIR, name + ".svg")
            png = os.path.join(ICON_DIR, name + ".png")
            url = "file:///" + svg.replace("\\", "/").replace(" ", "%20")
            subprocess.run(
                [
                    chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    "--no-first-run", "--no-default-browser-check",
                    "--user-data-dir=" + profile,
                    "--default-background-color=00000000",
                    "--window-size=1024,1024", "--screenshot=" + png, url,
                ],
                check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            print("rendered", png)
    finally:
        shutil.rmtree(profile, ignore_errors=True)


def resize(src, size):
    img = Image.open(src).convert("RGBA")
    return img.resize((size, size), Image.LANCZOS)


def write_mipmaps():
    for density, (legacy, adaptive) in DENSITIES.items():
        folder = os.path.join(RES, "mipmap-" + density)
        os.makedirs(folder, exist_ok=True)
        resize(os.path.join(ICON_DIR, "icon_full.png"), legacy).save(
            os.path.join(folder, "ic_launcher.png"), optimize=True)
        for layer in ("foreground", "background", "monochrome"):
            resize(os.path.join(ICON_DIR, f"icon_{layer}.png"), adaptive).save(
                os.path.join(folder, f"ic_launcher_{layer}.png"), optimize=True)
        print("wrote", folder)

    anydpi = os.path.join(RES, "mipmap-anydpi-v26")
    os.makedirs(anydpi, exist_ok=True)
    with open(os.path.join(anydpi, "ic_launcher.xml"), "w", encoding="utf-8", newline="\n") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@mipmap/ic_launcher_background" />\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
            '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n'
            '</adaptive-icon>\n'
        )
    print("wrote", anydpi)


if __name__ == "__main__":
    if "--no-render" not in sys.argv:
        render()
    write_mipmaps()
