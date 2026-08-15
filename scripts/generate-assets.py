#!/usr/bin/env python3
"""Generate Harbor's layered tvOS app icon and Top Shelf asset catalog."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = Image.open(ROOT / "Resources" / "AppIconSource.png").convert("RGBA")
ASSETS = ROOT / "Assets.xcassets"
BRAND = ASSETS / "App Icon & Top Shelf Image.brandassets"
BACKGROUND = (13, 17, 23, 255)
FULL_BLEED = SOURCE.getpixel((2, 2))[3] > 250
LANCZOS = getattr(Image, "Resampling", Image).LANCZOS


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def cover(width: int, height: int) -> Image.Image:
    scale = max(width / SOURCE.width, height / SOURCE.height)
    image = SOURCE.resize((round(SOURCE.width * scale), round(SOURCE.height * scale)), LANCZOS)
    left = (image.width - width) // 2
    top = (image.height - height) // 2
    return image.crop((left, top, left + width, top + height))


def centered(width: int, height: int, fraction: float) -> Image.Image:
    image = Image.new("RGBA", (width, height), BACKGROUND)
    target_height = int(height * fraction)
    scale = target_height / SOURCE.height
    logo = SOURCE.resize((round(SOURCE.width * scale), target_height), LANCZOS)
    image.paste(logo, ((width - logo.width) // 2, (height - logo.height) // 2), logo)
    return image


def icon_art(width: int, height: int) -> Image.Image:
    return cover(width, height) if FULL_BLEED else centered(width, height, 0.72)


def shelf_art(width: int, height: int) -> Image.Image:
    return centered(width, height, 0.55)


def transparent(width: int, height: int) -> Image.Image:
    return Image.new("RGBA", (width, height), (0, 0, 0, 0))


def image_set(directory: Path, size: tuple[int, int], filename: str, renderer) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    width, height = size
    renderer(width, height).save(directory / filename)
    filename_2x = filename.replace("_1x", "_2x")
    renderer(width * 2, height * 2).save(directory / filename_2x)
    write_json(
        directory / "Contents.json",
        {
            "images": [
                {"idiom": "tv", "filename": filename, "scale": "1x"},
                {"idiom": "tv", "filename": filename_2x, "scale": "2x"},
            ],
            "info": {"author": "xcode", "version": 1},
        },
    )


def image_stack(directory: Path, width: int, height: int) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    layers = []
    for name in ("Back", "Middle", "Front"):
        layer = directory / f"{name}.imagestacklayer"
        content = layer / "Content.imageset"
        image_set(content, (width, height), "icon_1x.png", icon_art if name == "Back" else transparent)
        write_json(layer / "Contents.json", {"info": {"author": "xcode", "version": 1}})
        layers.append({"filename": f"{name}.imagestacklayer"})
    write_json(
        directory / "Contents.json",
        {"layers": layers, "info": {"author": "xcode", "version": 1}},
    )


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    BRAND.mkdir(parents=True, exist_ok=True)
    write_json(ASSETS / "Contents.json", {"info": {"author": "xcode", "version": 1}})
    image_stack(BRAND / "App Icon.imagestack", 400, 240)
    image_stack(BRAND / "App Icon - App Store.imagestack", 1280, 768)
    image_set(BRAND / "Top Shelf Image.imageset", (1920, 720), "top_1x.png", shelf_art)
    image_set(BRAND / "Top Shelf Image Wide.imageset", (2320, 720), "topwide_1x.png", shelf_art)
    write_json(
        BRAND / "Contents.json",
        {
            "assets": [
                {"filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"},
                {"filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"},
                {"filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"},
                {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"},
            ],
            "info": {"author": "xcode", "version": 1},
        },
    )
    print(f"Generated {BRAND.relative_to(ROOT)} (full_bleed={FULL_BLEED})")


if __name__ == "__main__":
    main()
