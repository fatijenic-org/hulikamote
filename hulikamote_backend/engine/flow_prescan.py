"""
flow_prescan.py - learn the traffic flow of a recorded clip BEFORE judging it.

Online learning alone misses wrong-way cars that appear before the flow is known. For recorded footage the
whole clip is available, so the first `seconds` of it are run through detection + tracking once (no
specialists, no judging, no evidence) to teach the FlowField; then tracking is reset and the real pass
starts with the flow already known.
"""
import cv2

PRESCAN_EVERY_N_FRAMES = 3      # same cadence as the live monitor (10 inferences a second on 30 fps video)


def prescan_flow(pipeline, video_path, seconds: float = 60.0, every: int = PRESCAN_EVERY_N_FRAMES, start_seconds: float = 0.0) -> dict:
    """Teach pipeline.flow from `seconds` of the video, from `start_seconds` on (0 = the very start; the dashboard's trim
    step starts later). Times count from there, as in the real pass. Returns the field's summary."""
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        return {"votes": 0, "judged_cells": 0}
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    if start_seconds > 0:
        cap.set(cv2.CAP_PROP_POS_FRAMES, round(start_seconds * fps))
    width = height = 0
    pipeline.learn_only = True
    try:
        n = 0
        while n / fps < seconds:
            ok, frame = cap.read()
            if not ok:
                break
            n += 1
            if n % every:
                continue
            height, width = frame.shape[:2]
            pipeline.process_frame(frame, n, timestamp=n / fps)
    finally:
        pipeline.learn_only = False
        cap.release()
        pipeline.reset_tracking()
    return pipeline.flow.summary(width or 1, height or 1)
