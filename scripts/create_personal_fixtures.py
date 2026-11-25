"""Generate local media for the simulator's comment and background audio checks."""
from array import array
import math
from pathlib import Path
import struct
import subprocess
import wave
import zlib

output = Path("build/test-media")
output.mkdir(parents=True, exist_ok=True)
width, height = 360, 640
rows = []
for y in range(height):
    row = bytearray()
    for x in range(width):
        border = x < 12 or x >= width - 12 or y < 12 or y >= height - 12
        row.extend((255, 209, 70) if border else (35, 100 + y // 6, 190))
    rows.append(b"\0" + bytes(row))

def chunk(name, data):
    return struct.pack(">I", len(data)) + name + data + struct.pack(">I", zlib.crc32(name + data))

png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">2I5B", width, height, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(b"".join(rows)))
png += chunk(b"IEND", b"")
(output / "photo.png").write_bytes(png)
samples = array("h", (int(2400 * math.sin(2 * math.pi * 440 * n / 44100)) for n in range(44100)))
with wave.open(str(output / "music.wav"), "wb") as audio:
    audio.setnchannels(1)
    audio.setsampwidth(2)
    audio.setframerate(44100)
    for _ in range(120):
        audio.writeframes(samples.tobytes())
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-loop", "1", "-i", str(output / "photo.png"),
                "-i", str(output / "music.wav"), "-t", "120", "-r", "5", "-c:v", "libx264", "-pix_fmt", "yuv420p",
                "-c:a", "aac", "-b:a", "64k",
                "-movflags", "+faststart", str(output / "video.mp4")], check=True)
