**1. Your two goals are right. I'd phrase them as two research questions:**
- **Coverage:** how many of the 13–14 violations can the system catch?
- **Accuracy:** how well does it catch them, and how does that change when we swap in different detection models?

**2. Running everything at once is possible.**
All the violations share one detector (the "eyes") and one tracker (the "memory"). Each violation is just a small rule on top, and the rules cost almost nothing to run. What actually slows things down is the extra models: plate, helmet and cabin. So "everything on" works, it's just slower.

**3. Framing: test each violation alone first, then all together.**
- **Alone:** one violation per test, using clips made for it. This tells you exactly how good each rule is, and a mistake can't be blamed on another rule.
- **All together:** one final run on mixed footage with everything on. This proves the full system works as one, and gives you its real speed.

**4. Benchmark at two levels.**

| Level | What it tests | How | Score |
|---|---|---|---|
| **Detector** | Does it see cars, motorcycles, people and plates correctly? | Hand-labeled test photos | mAP@50 (your thesis metric) |
| **System** | Does it catch the actual violation? | Clips where you counted every violation by hand | Correct catches, wrong alarms (FP) and misses (FN), turned into precision and recall, plus whether the ticket has the right plate, type and photo |

**Rules for a fair comparison:**
- Use the same test clips for every model. Never train on them.
- Change only the detector (YOLOv8, YOLO11, YOLO26, your fine-tuned one). Keep the rules the same.
- Aim for about 10–20 real violations per type, with mixed conditions (day/night, busy/quiet).

**Final result: one table.** Violations go down the side and models across the top, with precision and recall in each cell, plus mAP and speed at the bottom. That table answers both goals.

Next, I can build the tool that runs a clip and fills in this table automatically (handover next step 2). Just say go.