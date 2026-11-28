"""Export fixed-size RIFE 4.25 for Core ML. Used only at build time."""

import argparse
import hashlib
from pathlib import Path
import urllib.request

import coremltools as ct
import torch
import torch.nn as nn
import torch.nn.functional as F
from safetensors.numpy import load_file

WIDTH, HEIGHT = 320, 192
WEIGHT_URL = (
    "https://huggingface.co/mlx-community/RIFE-4.25/resolve/"
    "6b650eaa5664aab280119511fe944861491aa15e/model.safetensors"
)
WEIGHT_SHA = "40bd5bdc9b41d22ad2fad79da325dcd68988a90d8b8e8fb7b67ed5eedebccf5f"


class Conv(nn.Module):
    def __init__(self, source, dest):
        super().__init__()
        self.conv = nn.Conv2d(source, dest, 3, 2, 1)

    def forward(self, x):
        return F.leaky_relu(self.conv(x), 0.2)


class ResConv(nn.Module):
    def __init__(self, channels):
        super().__init__()
        self.conv = nn.Conv2d(channels, channels, 3, 1, 1)
        self.beta = nn.Parameter(torch.ones(1, channels, 1, 1))

    def forward(self, x):
        return F.leaky_relu(x + self.conv(x) * self.beta, 0.2)


class Encoder(nn.Module):
    def __init__(self):
        super().__init__()
        self.cnn0 = nn.Conv2d(3, 16, 3, 2, 1)
        self.cnn1 = nn.Conv2d(16, 16, 3, 1, 1)
        self.cnn2 = nn.Conv2d(16, 16, 3, 1, 1)
        self.cnn3 = nn.ConvTranspose2d(16, 4, 4, 2, 1)

    def forward(self, x):
        for layer in (self.cnn0, self.cnn1, self.cnn2):
            x = F.leaky_relu(layer(x), 0.2)
        return self.cnn3(x)


def resize(x, size):
    return F.interpolate(x, size=size, mode="bilinear", align_corners=False)


class IFBlock(nn.Module):
    def __init__(self, inputs, channels, scale):
        super().__init__()
        self.scale = scale
        self.small = (HEIGHT // scale, WIDTH // scale)
        self.conv0 = nn.Sequential(Conv(inputs, channels // 2), Conv(channels // 2, channels))
        self.convblock = nn.Sequential(*(ResConv(channels) for _ in range(8)))
        self.lastconv = nn.ConvTranspose2d(channels, 52, 4, 2, 1)

    def forward(self, x, flow=None):
        if self.scale != 1:
            x = resize(x, self.small)
        if flow is not None:
            if self.scale != 1:
                flow = resize(flow, self.small) / self.scale
            x = torch.cat((x, flow), dim=1)
        x = self.convblock(self.conv0(x))
        x = F.pixel_shuffle(self.lastconv(x), 2)
        if self.scale != 1:
            x = resize(x, (HEIGHT, WIDTH))
        return x[:, :4] * self.scale, x[:, 4:5], x[:, 5:]


class RIFE(nn.Module):
    def __init__(self):
        super().__init__()
        self.encode = Encoder()
        self.block0 = IFBlock(15, 192, 16)
        self.block1 = IFBlock(28, 128, 8)
        self.block2 = IFBlock(28, 96, 4)
        self.block3 = IFBlock(28, 64, 2)
        self.block4 = IFBlock(28, 32, 1)
        y, x = torch.meshgrid(torch.linspace(-1, 1, HEIGHT), torch.linspace(-1, 1, WIDTH), indexing="ij")
        self.register_buffer("grid", torch.stack((x, y), dim=-1).unsqueeze(0), persistent=False)
        self.register_buffer("grid_scale", torch.tensor([2 / (WIDTH - 1), 2 / (HEIGHT - 1)]), persistent=False)
        self.register_buffer("phase", torch.full((1, 1, HEIGHT, WIDTH), 0.5), persistent=False)

    def warp(self, tensor, flow):
        coords = self.grid + flow.permute(0, 2, 3, 1) * self.grid_scale
        return F.grid_sample(tensor, coords, mode="bilinear", padding_mode="border", align_corners=True)

    def forward(self, previous, current):
        f0, f1 = self.encode(previous), self.encode(current)
        flow, mask, feat = self.block0(torch.cat((previous, current, f0, f1, self.phase), dim=1))
        for block in (self.block1, self.block2, self.block3, self.block4):
            fwd, back = flow[:, :2], flow[:, 2:4]
            warped = (
                self.warp(previous, fwd), self.warp(current, back),
                self.warp(f0, fwd), self.warp(f1, back),
            )
            update, mask, feat = block(torch.cat((*warped, self.phase, mask, feat), dim=1), flow)
            flow = flow + update
        mask = torch.sigmoid(mask)
        result = self.warp(previous, flow[:, :2]) * mask + self.warp(current, flow[:, 2:4]) * (1 - mask)
        return result.clamp(0, 1) * 255


def read_weights(path):
    if not path.exists():
        for attempt in range(3):
            try:
                with urllib.request.urlopen(WEIGHT_URL, timeout=45) as response:
                    data = response.read(22_674_263)
                if hashlib.sha256(data).hexdigest() != WEIGHT_SHA:
                    raise ValueError("RIFE weights SHA-256 mismatch")
                path.write_bytes(data)
                break
            except OSError:
                if attempt == 2:
                    raise
    if hashlib.sha256(path.read_bytes()).hexdigest() != WEIGHT_SHA:
        raise ValueError("RIFE weights SHA-256 mismatch")
    weights = {}
    for key, value in load_file(str(path)).items():
        if value.ndim == 4:
            transpose = (3, 0, 1, 2) if key.endswith(("lastconv.weight", "encode.cnn3.weight")) else (0, 3, 1, 2)
            value = value.transpose(transpose)
        weights[key] = torch.from_numpy(value.copy())
    return weights


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("--weights", type=Path, required=True)
    parser.add_argument("--graph-only", action="store_true")
    args = parser.parse_args()
    torch.set_num_threads(2)
    model = RIFE().eval()
    model.load_state_dict(read_weights(args.weights), strict=True)
    shape = (1, 3, HEIGHT, WIDTH)
    example = torch.zeros(shape)
    with torch.inference_mode():
        traced = torch.jit.trace(model, (example, example), check_trace=False)
        ct_model = ct.convert(
            traced,
            convert_to="milinternal" if args.graph_only else "mlprogram",
            inputs=[ct.ImageType(name=name, shape=shape, scale=1 / 255) for name in ("previous", "current")],
            outputs=[ct.ImageType(name="midpoint")],
            minimum_deployment_target=ct.target.iOS18,
            compute_precision=ct.precision.FLOAT16,
            skip_model_load=True,
        )
    if args.graph_only:
        print("Converted Core ML graph operations:", len(ct_model.functions["main"].operations))
        return
    ct_model.author = "Practical-RIFE contributors"
    ct_model.license = "MIT"
    ct_model.short_description = "RIFE 4.25, fixed 320×192, midpoint interpolator"
    ct_model.save(str(args.output))


if __name__ == "__main__":
    main()
