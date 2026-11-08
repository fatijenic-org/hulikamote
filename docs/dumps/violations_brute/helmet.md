# Helmet Detection — Algorithmic & Mathematical Foundations

This document details the fundamental algorithms for isolating a motorcycle rider's head and determining the presence of a helmet using raw pixel mathematics (without deep learning).

---

## 1. The Head Extraction (Grid Slicing)

In Python, an image is treated as a 2D grid. We extract the head by slicing the top 25% of the motorcycle's bounding box.

### Visual Slicing Example
Imagine a 10x10 pixel grid where the AI found a motorcycle (H = Head, M = Motorcycle, . = Background).

```text
    0  1  2  3  4  5  6  7  8  9  (Columns / X)
0   .  .  .  .  .  .  .  .  .  .
1   .  .  .  .  .  .  .  .  .  .
2   .  .  .  H  H  H  H  .  .  .   <-- Box starts here (y=2)
3   .  .  .  H  H  H  H  .  .  .
4   .  .  .  M  M  M  M  .  .  .
5   .  .  .  M  M  M  M  .  .  .
6   .  .  .  M  M  M  M  .  .  .
7   .  .  .  M  M  M  M  .  .  .
8   .  .  .  M  M  M  M  .  .  .
9   .  .  .  M  M  M  M  .  .  .
             ^        ^
    (x=3)----|        |----(x+width=7)
```

**The Math:**
* Box Starting Coordinates: `y = 2`, `x = 3`
* Box Dimensions: `height = 8`, `width = 4`
* Head Height Math: `head_height = 8 * 0.25 = 2`

**The Python Slicing Code:**
```python
head_crop = image[y : y + head_height,  x : x + width]
head_crop = image[2 : 4,                3 : 7]
```
*(Result: Python extracts Rows 2-3 and Columns 3-6, isolating only the 'H' pixels).*

---

## 2. The Skin Tone Loop (Color Thresholding)

Once the head is isolated, we loop through every pixel to check if it matches human skin.

```python
skin_pixel_count = 0
for pixel in head_crop:
    r, g, b = pixel

    # Universal mathematical rule for skin tone in RGB
    if r > 95 and g > 40 and b > 20 and r > g and r > b:
        skin_pixel_count += 1
```

### The Universal RGB Rule Explained
This is a standard heuristic in Computer Vision that successfully identifies human skin under normal daylight lighting, regardless of ethnicity.

> **Academic Citation:** 
> Kovac, J., Peer, P., & Solina, F. (2003). *"Human skin color clustering for face detection"*. In Proceedings of IEEE Region 8 EUROCON 2003. Computer as a Tool. (Vol. 2, pp. 144-148). 

* **Base limits (`r > 95`, `g > 40`, `b > 20`):** These ensure the pixel is bright enough. If the numbers are too low, the pixel is just a dark shadow or black hair/clothing.
* **The Color Dominance (`r > g` and `r > b`):** Because of human biology (blood flow and melanin), **Red is always the most dominant color value in human skin.** 
  * If Green is higher than Red (`g > r`), the pixel belongs to grass or a green helmet.
  * If Blue is higher than Red (`b > r`), the pixel belongs to the sky or a blue helmet.
  * Enforcing that Red is strictly the highest number instantly filters out non-human objects.
