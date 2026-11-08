import abc
from typing import Any, List
import numpy as np

class BaseTracker(abc.ABC):
    """
    Abstract interface for vehicle trackers.
    """
    @abc.abstractmethod
    def update_with_detections(self, sv_dets: Any, frame: np.ndarray) -> Any:
        """
        Updates the tracker with new YOLO detections and returns the tracked results.
        
        Args:
            sv_dets: supervision.Detections object.
            frame: Raw BGR frame (numpy array) if needed by tracker.
            
        Returns:
            supervision.Detections object augmented with `tracker_id`.
        """
        pass

class ByteTrackStrategy(BaseTracker):
    """
    Wraps supervision.ByteTrack. Fast, IoU-based tracking.
    """
    # ====================================================================================
    # [LOCKED BY USER]: DO NOT MODIFY THESE TRACKER PARAMETERS WITHOUT EXPLICIT PERMISSION
    # ====================================================================================
    def __init__(self, lost_track_buffer: int = 90, minimum_matching_threshold: float = 0.35):
        import supervision as sv
        self.tracker = sv.ByteTrack(
            lost_track_buffer=lost_track_buffer,          # 60→90: longer buffer before a lost track is purged
            minimum_matching_threshold=minimum_matching_threshold  # 0.2→0.35: better re-association for fast vehicles
        )
        
    def update_with_detections(self, sv_dets: Any, frame: np.ndarray) -> Any:
        return self.tracker.update_with_detections(sv_dets)


class DeepSortStrategy(BaseTracker):
    """
    Wraps the DeepSORT tracker (CNN-based appearance matching).
    """
    # ====================================================================================
    # [LOCKED BY USER]: DO NOT MODIFY THESE TRACKER PARAMETERS WITHOUT EXPLICIT PERMISSION
    # ====================================================================================
    def __init__(self, lost_track_buffer: int = 90, max_dist: float = 0.4):
        import os
        import torch
        from engine.deep_sort.deep_sort import DeepSort
        
        use_cuda = torch.cuda.is_available()
        ckpt_path = os.path.join(os.path.dirname(__file__), "deep_sort", "deep", "checkpoint", "ckpt.t7")
        
        self.tracker = DeepSort(
            model_path=ckpt_path,
            max_dist=max_dist,          # 0.2→0.4: looser appearance match — survives angle/lighting changes
            min_confidence=0.1,
            nms_max_overlap=0.5,
            max_iou_distance=0.7,
            max_age=lost_track_buffer,  # 60→90: longer occlusion buffer before a track is killed
            n_init=3,                   # 1→3: require 3 consecutive confirmed frames before locking an ID
            nn_budget=100,
            use_cuda=use_cuda
        )

    def update_with_detections(self, sv_dets: Any, frame: np.ndarray) -> Any:
        import supervision as sv
        
        # DeepSORT expects: [x, y, w, h] format for boxes and confidences
        if len(sv_dets.xyxy) == 0:
            return sv.Detections.empty()
            
        # Convert xyxy to CENTER xywh (DeepSort.update subtracts w/2,h/2 itself and crops ReID around the centre)
        boxes_xywh = []
        for (x1, y1, x2, y2) in sv_dets.xyxy:
            boxes_xywh.append([(x1 + x2) / 2.0, (y1 + y2) / 2.0, x2 - x1, y2 - y1])
        
        boxes_xywh = np.array(boxes_xywh)
        confidences = sv_dets.confidence
        
        # We need RGB for DeepSORT features
        import cv2
        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        
        # Returns: list of [x1, y1, x2, y2, track_id]
        outputs, _ = self.tracker.update(boxes_xywh, confidences, frame_rgb)
        
        if len(outputs) == 0:
            return sv.Detections.empty()
            
        # Re-pack into sv.Detections
        # Note: DeepSORT might drop some boxes if they don't meet n_init or match.
        # We must re-map class_ids from YOLO, but DeepSORT output doesn't return class_id out of the box.
        # We will match them back to YOLO detections via IoU if needed, OR just infer class from original sv_dets by IoU overlap.
        
        tracked_xyxy = []
        tracker_ids = []
        tracked_confidences = []
        tracked_class_ids = []
        
        for output in outputs:
            tx1, ty1, tx2, ty2, tid = output
            tracked_xyxy.append([tx1, ty1, tx2, ty2])
            tracker_ids.append(tid)
            
            # Find the best matching original detection to inherit class_id and confidence
            best_iou = 0
            best_idx = 0
            for i, (ox1, oy1, ox2, oy2) in enumerate(sv_dets.xyxy):
                # Calculate IoU
                ix1 = max(tx1, ox1)
                iy1 = max(ty1, oy1)
                ix2 = min(tx2, ox2)
                iy2 = min(ty2, oy2)
                iw = max(0, ix2 - ix1)
                ih = max(0, iy2 - iy1)
                inter = iw * ih
                union = (tx2-tx1)*(ty2-ty1) + (ox2-ox1)*(oy2-oy1) - inter
                iou = inter / union if union > 0 else 0
                if iou > best_iou:
                    best_iou = iou
                    best_idx = i
                    
            tracked_confidences.append(sv_dets.confidence[best_idx])
            tracked_class_ids.append(sv_dets.class_id[best_idx])
            
        return sv.Detections(
            xyxy=np.array(tracked_xyxy),
            confidence=np.array(tracked_confidences),
            class_id=np.array(tracked_class_ids),
            tracker_id=np.array(tracker_ids)
        )
