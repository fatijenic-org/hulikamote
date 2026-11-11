# Make the vehicle model better: your steps

**Why:** the model is good on web photos but misses riders on your camera view. It needs pictures from your own clips.

**Test clips:** do NOT label frames from clips `e10b2564` (street) and `ac483b8b` (night). Keep them as your honest test.

---

## Step 1. Get more frames (about 15 minutes)

1. Open **Forensic Analyzer** > **Harvest** tab. It collects frames by itself.
2. Each clip gives 8 frames, and only if the analysis **kept its video**. 26 analyses have video now.
3. For more frames, analyze more clips. In the wizard, tick **Keep the uploaded video**.
4. Use different roads and times: day, night, rain, crowded.

**Goal:** 300 labelled frames. Less is okay to start. 100 is the minimum worth training.

## Step 2. Label the frames (the main work)

1. In **Harvest**, open the **Vehicles** tile. One frame shows at a time, with the model's guesses drawn.
2. Fix it. Keys:
   - **Enter** = all boxes are right
   - **Drag** = draw a new box (pick the class first, or press keys **1-9**)
   - **Drag a corner** = fix a box. **Delete** = remove the picked box
   - **N** = nothing here. **S** = not sure. **Esc** = close
3. Box EVERY one of these:
   - motorcycle, car, truck
   - bus = full-size bus only
   - jeepney = long open-sided vehicle with benches
   - tricycle = motorcycle with a sidecar
   - person = each **rider and passenger** on a motorcycle or tricycle (not people who walk)
4. A missing box teaches the model to ignore that vehicle. Do not skip small or far ones.
5. Do the hard frames first: crowded roads, night, riders seen from behind.
6. Plan 1 to 2 minutes per frame. Do 100 frames, then continue if you can.

## Step 3. Add them to the dataset

1. Do this only when the vehicle model is **not training**.
2. In the Harvest page press the **Add** button for Vehicles. Or run this in a terminal:

```
cd C:\Users\nekol\Desktop\istqm_framework\k_dev\huli-kamote
hulikamote_backend\venv\Scripts\python.exe training_lab\harvest.py accept primary_anchor
```

Most frames go to training. About 15% go to val. None go to test.

## Step 4. Prepare the training

1. Plug in the laptop. Turn off sleep. Close other GPU programs.
2. Open `training_lab\configs\training_config.yaml`. Change `batch: 16` to `batch: 8`. Save. (A bigger picture needs more memory.)

## Step 5. Train

Run in a terminal. Keep the window open. Do not close it.

```
cd C:\Users\nekol\Desktop\istqm_framework\k_dev\huli-kamote\training_lab
..\hulikamote_backend\venv\Scripts\python.exe scripts\train.py --model primary_anchor --epochs 30 --imgsz 960 --batch 8
```

- It takes about **11 hours**.
- A backend restart does not stop it.
- If you get "CUDA out of memory": use `--batch 4`.
- If it stops: open **Models** > **Vehicles** > **Continue**.
- Do not start two trainings at once.

## Step 6. Check before you use it

1. Open **Models** > **Vehicles**. The new version shows in the list. It is **not live**.
2. Open the new version. Press **Check per type**. Look at person, motorcycle, tricycle, jeepney.
3. Tell me: "check the new vehicle model on my clips". I compare it with the live model on the two test clips.
4. Press **Use this** only if it finds the riders better. It works from the next analysis or live frame.

---

## Not built yet (ask me)

- **Repeat real frames:** your real frames are few next to 28,000 web photos. I can add "repeat harvested frames 4 times" before you train. This helps a lot.
- **More frames per clip:** the limit is 8 now. I can raise it to 40.
- **Bigger model:** `base_model: yolov8s.pt` in the same config file. More accurate, but slower on the laptop.
