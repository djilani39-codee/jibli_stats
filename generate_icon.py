#!/usr/bin/env python3
"""Generate dashboard icon PNG from SVG"""
import subprocess
import sys
from pathlib import Path

svg_path = Path(__file__).parent / "assets" / "icon" / "dashboard_icon.svg"
png_path = Path(__file__).parent / "assets" / "icon" / "dashboard_icon.png"

# Try using ImageMagick convert command
try:
    subprocess.run([
        "convert",
        "-background", "none",
        "-density", "192",
        str(svg_path),
        "-resize", "512x512",
        str(png_path)
    ], check=True)
    print(f"✓ Icon created: {png_path}")
except FileNotFoundError:
    print("ImageMagick not found. Try installing with:")
    print("  choco install imagemagick")
    print("\nOr use an online converter:")
    print("  https://cloudconvert.com/svg-to-png")
    print(f"  Convert {svg_path} to {png_path}")
    sys.exit(1)
except subprocess.CalledProcessError as e:
    print(f"Error converting SVG to PNG: {e}")
    sys.exit(1)
