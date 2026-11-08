"""
export_esrgan_standalone.py
Exports the downloaded RealESRGAN_x4plus.pth to ONNX without needing basicsr.
The RRDBNet architecture is defined inline to avoid torchvision incompatibility.
"""
import torch
import torch.nn as nn
from pathlib import Path

# ─── Inline RRDBNet architecture (from xinntao/Real-ESRGAN, Apache 2.0) ───────

class ResidualDenseBlock(nn.Module):
    def __init__(self, num_feat=64, num_grow_ch=32):
        super().__init__()
        self.conv1 = nn.Conv2d(num_feat, num_grow_ch, 3, 1, 1)
        self.conv2 = nn.Conv2d(num_feat + num_grow_ch, num_grow_ch, 3, 1, 1)
        self.conv3 = nn.Conv2d(num_feat + 2 * num_grow_ch, num_grow_ch, 3, 1, 1)
        self.conv4 = nn.Conv2d(num_feat + 3 * num_grow_ch, num_grow_ch, 3, 1, 1)
        self.conv5 = nn.Conv2d(num_feat + 4 * num_grow_ch, num_feat, 3, 1, 1)
        self.lrelu = nn.LeakyReLU(negative_slope=0.2, inplace=True)

    def forward(self, x):
        x1 = self.lrelu(self.conv1(x))
        x2 = self.lrelu(self.conv2(torch.cat((x, x1), 1)))
        x3 = self.lrelu(self.conv3(torch.cat((x, x1, x2), 1)))
        x4 = self.lrelu(self.conv4(torch.cat((x, x1, x2, x3), 1)))
        x5 = self.conv5(torch.cat((x, x1, x2, x3, x4), 1))
        return x5 * 0.2 + x


class RRDB(nn.Module):
    def __init__(self, num_feat, num_grow_ch=32):
        super().__init__()
        self.rdb1 = ResidualDenseBlock(num_feat, num_grow_ch)
        self.rdb2 = ResidualDenseBlock(num_feat, num_grow_ch)
        self.rdb3 = ResidualDenseBlock(num_feat, num_grow_ch)

    def forward(self, x):
        out = self.rdb1(x)
        out = self.rdb2(out)
        out = self.rdb3(out)
        return out * 0.2 + x


class RRDBNet(nn.Module):
    def __init__(self, num_in_ch=3, num_out_ch=3, scale=4, num_feat=64, num_block=23, num_grow_ch=32):
        super().__init__()
        self.scale = scale
        self.conv_first = nn.Conv2d(num_in_ch, num_feat, 3, 1, 1)
        self.body = nn.Sequential(*[RRDB(num_feat, num_grow_ch) for _ in range(num_block)])
        self.conv_body = nn.Conv2d(num_feat, num_feat, 3, 1, 1)
        # Upsample
        self.conv_up1 = nn.Conv2d(num_feat, num_feat, 3, 1, 1)
        self.conv_up2 = nn.Conv2d(num_feat, num_feat, 3, 1, 1)
        self.conv_hr  = nn.Conv2d(num_feat, num_feat, 3, 1, 1)
        self.conv_last = nn.Conv2d(num_feat, num_out_ch, 3, 1, 1)
        self.lrelu = nn.LeakyReLU(negative_slope=0.2, inplace=True)

    def forward(self, x):
        feat = self.conv_first(x)
        body_feat = self.conv_body(self.body(feat))
        feat = feat + body_feat
        feat = self.lrelu(self.conv_up1(nn.functional.interpolate(feat, scale_factor=2, mode='nearest')))
        feat = self.lrelu(self.conv_up2(nn.functional.interpolate(feat, scale_factor=2, mode='nearest')))
        out  = self.conv_last(self.lrelu(self.conv_hr(feat)))
        return out


# ─── Export ───────────────────────────────────────────────────────────────────

PTH_PATH = Path(__file__).parent / "_esrgan_temp" / "RealESRGAN_x4plus.pth"
ONNX_OUT = Path(__file__).resolve().parent.parent.parent / "hulikamote_backend" / "models" / "realesrgan.onnx"

print(f"Loading weights from {PTH_PATH}...")
model = RRDBNet(num_in_ch=3, num_out_ch=3, scale=4, num_feat=64, num_block=23, num_grow_ch=32)
state = torch.load(str(PTH_PATH), map_location="cpu")

# RealESRGAN stores weights under 'params_ema'
key = "params_ema" if "params_ema" in state else "params" if "params" in state else None
model.load_state_dict(state[key] if key else state, strict=True)
model.eval()

print("Exporting to ONNX...")
dummy = torch.randn(1, 3, 80, 320)  # typical plate crop
torch.onnx.export(
    model, dummy, str(ONNX_OUT),
    opset_version=11,
    input_names=["input"],
    output_names=["output"],
    dynamic_axes={"input": {2: "height", 3: "width"}, "output": {2: "height", 3: "width"}}
)

print(f"✅ Exported to {ONNX_OUT}")

import onnxruntime as ort
sess = ort.InferenceSession(str(ONNX_OUT))
print(f"✅ Verification OK. Input shape: {sess.get_inputs()[0].shape}")
print("   Restart your FastAPI server to activate GAN enhancement.")
