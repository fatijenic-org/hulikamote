import numpy as np

class NumpySlicer:
    """
    Handles cropping the primary bounding boxes from the main frame and
    translating specialist coordinates back to the global frame.
    """
    @staticmethod
    def crop_box(frame: np.ndarray, bbox: list[int]) -> np.ndarray:
        """
        Crop a bounding box from the frame.
        bbox is [x, y, w, h] in global coordinates.
        """
        x, y, w, h = bbox
        h_frame, w_frame = frame.shape[:2]
        
        # Ensure bounds
        x1 = max(0, x)
        y1 = max(0, y)
        x2 = min(w_frame, x + w)
        y2 = min(h_frame, y + h)
        
        if x2 <= x1 or y2 <= y1:
            return np.zeros((1, 1, 3), dtype=np.uint8)
            
        return frame[y1:y2, x1:x2].copy()

    @staticmethod
    def translate_coordinates(local_bbox: list[int], parent_bbox: list[int]) -> list[int]:
        """
        Translates a local bounding box (from a crop) to global frame coordinates.
        local_bbox: [x, y, w, h] relative to the parent crop
        parent_bbox: [x, y, w, h] relative to the global frame
        """
        lx, ly, lw, lh = local_bbox
        px, py, pw, ph = parent_bbox
        
        global_x = px + lx
        global_y = py + ly
        
        return [global_x, global_y, lw, lh]
        
    @staticmethod
    def calculate_iou(boxA: list[int], boxB: list[int]) -> float:
        """Calculate Intersection over Union (IoU) of two bounding boxes [x, y, w, h]"""
        xA = max(boxA[0], boxB[0])
        yA = max(boxA[1], boxB[1])
        xB = min(boxA[0] + boxA[2], boxB[0] + boxB[2])
        yB = min(boxA[1] + boxA[3], boxB[1] + boxB[3])

        interArea = max(0, xB - xA) * max(0, yB - yA)
        if interArea == 0: return 0.0

        boxAArea = boxA[2] * boxA[3]
        boxBArea = boxB[2] * boxB[3]
        return interArea / float(boxAArea + boxBArea - interArea)
