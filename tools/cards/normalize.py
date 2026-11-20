#!/usr/bin/env python3
"""Normalize Ghaf's card artwork and build a dark contact sheet.

Run with: python3 tools/cards/normalize.py
Requires Pillow: python3 -m pip install Pillow
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps
from PIL import ImageCms


ROOT = Path(__file__).resolve().parents[2]
CARDS = ROOT / "Ghaf/Resources/Cards"
CATALOG = CARDS / "card-catalog.json"
TARGET_RATIO = 85.60 / 53.98
NORMALIZED_COMMENT = b"ghaf-cards-normalized-v1"


def normalized_crop(image: Image.Image) -> Image.Image:
    if image.info.get("comment") == NORMALIZED_COMMENT:
        return image.convert("RGB")

    image = ImageOps.exif_transpose(image).convert("RGBA")
    background = Image.new("RGBA", image.size, "white")
    image = Image.alpha_composite(background, image).convert("RGB")
    width, height = image.size
    source_width = width

    # Bank pages often bake a white page into the rounded card corners. Crop a
    # small inset only when a near-white corner shows that treatment.
    corners = [image.getpixel(point) for point in ((0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1))]
    if any(min(pixel) >= 242 for pixel in corners):
        inset = max(2, round(min(width, height) * 0.0125))
        image = image.crop((inset, inset, width - inset, height - inset))

    width, height = image.size
    if width / height > TARGET_RATIO:
        crop_width = round(height * TARGET_RATIO)
        left = (width - crop_width) // 2
        image = image.crop((left, 0, left + crop_width, height))
    else:
        crop_height = round(width / TARGET_RATIO)
        top = (height - crop_height) // 2
        image = image.crop((0, top, width, top + crop_height))

    output_width = 1200 if source_width >= 1200 else source_width
    output_height = round(output_width / TARGET_RATIO)
    if image.size != (output_width, output_height):
        image = image.resize((output_width, output_height), Image.Resampling.LANCZOS)
    return image


def contact_sheet(items: list[tuple[str, Image.Image]], path: Path) -> None:
    columns, tile_width, tile_height, label_height, gap = 6, 190, 120, 30, 12
    rows = (len(items) + columns - 1) // columns
    sheet = Image.new("RGB", (gap + columns * (tile_width + gap), gap + rows * (tile_height + label_height + gap)), (25, 26, 29))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    for index, (name, image) in enumerate(items):
        x = gap + (index % columns) * (tile_width + gap)
        y = gap + (index // columns) * (tile_height + label_height + gap)
        thumb = image.copy()
        thumb.thumbnail((tile_width, tile_height), Image.Resampling.LANCZOS)
        tile = Image.new("RGB", (tile_width, tile_height), (42, 43, 47))
        tile.paste(thumb, ((tile_width - thumb.width) // 2, (tile_height - thumb.height) // 2))
        sheet.paste(tile, (x, y))
        label = name.removesuffix(".jpg")
        draw.text((x, y + tile_height + 4), label[:29], fill=(230, 230, 232), font=font)
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path, "JPEG", quality=88, optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contact-sheet", type=Path, default=Path("/tmp/ghaf-cards-contact-sheet.jpg"))
    args = parser.parse_args()

    records = json.loads(CATALOG.read_text())
    images: list[tuple[str, Image.Image]] = []
    for record in records:
        path = CARDS / f"{record['id']}.jpg"
        if not path.is_file():
            raise FileNotFoundError(f"Catalog image is missing: {path}")
        with Image.open(path) as source:
            already_normalized = source.info.get("comment") == NORMALIZED_COMMENT
            image = normalized_crop(source)
        if not already_normalized:
            image.save(path, "JPEG", quality=88, optimize=True, subsampling=0,
                       icc_profile=ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes(),
                       comment=NORMALIZED_COMMENT)
        images.append((path.name, image))

    contact_sheet(images, args.contact_sheet)
    small = [(name, image.width) for name, image in images if image.width == 640]
    print(f"Normalized {len(images)} cards; contact sheet: {args.contact_sheet}")
    print(f"Still 640px ({len(small)}):")
    for name, width in small:
        print(f"  {name}: {width}px")


if __name__ == "__main__":
    main()
