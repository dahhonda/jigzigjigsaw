# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "pillow",
# ]
# ///

from __future__ import annotations

import argparse
from pathlib import Path
from textwrap import dedent

from PIL import Image

def main():
    parser = argparse.ArgumentParser(
        description=dedent("""\
            画像をrows行 x cols列に分割する。
            分割された画像は、元画像から拡張子を取り除いた名前のフォルダに保存される。
            元画像の縦幅がrowsで割り切れないか、横幅がcolsで割り切れない場合、エラー。
        """)
    )
    parser.add_argument("image", help="分割する画像のパス")
    parser.add_argument("rows", type=int, help="分割する行数")
    parser.add_argument("cols", type=int, help="分割する列数")

    args = parser.parse_args()
    split_image_grid(
        image_path=args.image,
        rows=args.rows,
        cols=args.cols,
    )

def split_image_grid(
    image_path: str | Path,
    rows: int,
    cols: int,
) -> None:
    """
    画像を縦 rows 行 × 横 cols 列に分割して保存する。
    画像サイズが rows, cols で割り切れない場合は ValueError を投げる。
    """
    image_path = Path(image_path)
    output_dir = Path(image_path).parent / Path(image_path).stem
    output_dir.mkdir(parents=True, exist_ok=True)

    with Image.open(image_path) as img:
        width, height = img.size

        if width % cols != 0 or height % rows != 0:
            raise ValueError(f" 画像サイズ ({width}x{height}) が cols={cols}, rows={rows} で割り切れない")

        tile_width = width // cols
        tile_height = height // rows

        for row in range(rows):
            for col in range(cols):
                left = col * tile_width
                upper = row * tile_height
                right = left + tile_width
                lower = upper + tile_height

                tile = img.crop((left, upper, right, lower))

                tile_filename = f"r{row:02d}_c{col:02d}.png"
                tile_path = output_dir / tile_filename
                tile.save(tile_path)



if __name__ == "__main__":
    main()
