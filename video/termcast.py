#!/usr/bin/env python3
"""termcast.py: run real shell commands and record them as a terminal video.

usage: python3 termcast.py <scene.json> <workdir>

Every command in the scene is executed for real, in the workshop folder, when the take is
recorded. What you see on screen is that command's actual output. Nothing is typed in by hand
and nothing is edited afterwards. A command that exits non-zero fails the take unless the scene
says the failure is expected ("ok_exit": [22]).

Writes <workdir>/raw.mp4 and <workdir>/beats.tsv (seconds since the start, beat name), the same
two files the web recorder writes, so the rest of the pipeline is shared.

scene.json:
{
  "title": "optional window title",
  "env": {"NAME": "value or $file:.state/app.claims-copilot.key"},   // never shown on screen
  "steps": [
    {"beat": "b1"},
    {"banner": "A line of plain text, like a comment"},
    {"show": "./workshop sim seen openai"},        // typed, then run; output appears
    {"show": "curl ...", "ok_exit": [22]},
    {"pause": 3},
    {"clear": true}
  ]
}
"""
import json
import os
import re
import subprocess
import sys
import time

from PIL import Image, ImageDraw, ImageFont

W, H, FPS = 1280, 720, 15
PAD_X, PAD_Y, TITLE_H = 28, 22, 34
FONT_SIZE = 19
BG, FG, DIM = (13, 17, 23), (214, 220, 228), (125, 135, 148)
GREEN, CYAN, YELLOW, RED, TITLE_BG = (86, 211, 100), (88, 196, 220), (230, 190, 80), (240, 110, 110), (28, 34, 44)
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def font(size, bold=False):
    for path, idx in (("/System/Library/Fonts/Menlo.ttc", 1 if bold else 0),
                      ("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 0)):
        if os.path.exists(path):
            return ImageFont.truetype(path, size, index=idx)
    return ImageFont.load_default()


F, FB = font(FONT_SIZE), font(FONT_SIZE, True)
CW = F.getlength("M")
LH = int(FONT_SIZE * 1.42)
COLS = int((W - 2 * PAD_X) // CW)
ROWS = (H - TITLE_H - PAD_Y - 150) // LH     # the bottom of the frame is left clear for the subtitle box


def wrap(text):
    out = []
    for line in text.split("\n"):
        line = line.expandtabs(4)
        if not line:
            out.append("")
        while line:
            out.append(line[:COLS])
            line = line[COLS:]
    return out


def colour_for(line, kind):
    if kind == "banner":
        return CYAN
    if kind == "cmd":
        return FG
    s = line.strip()
    if s.startswith("ok ") or s.startswith("ok\t"):
        return GREEN
    if s.startswith("==") :
        return YELLOW
    if re.match(r"^(HTTP )?[45]\d\d\b", s) or s.startswith("xx") or s.startswith("--"):
        return RED
    return FG


class Screen:
    def __init__(self, title):
        self.title = title
        self.lines = []          # (text, kind)
        self.frames = 0
        self.proc = None

    def start(self, path):
        self.proc = subprocess.Popen(
            ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
             "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-preset", "medium", "-crf", "18", path],
            stdin=subprocess.PIPE)

    def now(self):
        return self.frames / FPS

    def draw(self, cursor=False):
        img = Image.new("RGB", (W, H), BG)
        d = ImageDraw.Draw(img)
        d.rectangle([0, 0, W, TITLE_H], fill=TITLE_BG)
        for i, c in enumerate(((255, 95, 86), (255, 189, 46), (39, 201, 63))):
            d.ellipse([16 + i * 22, 10, 30 + i * 22, 24], fill=c)
        d.text((W / 2, TITLE_H / 2), self.title, font=font(15), fill=DIM, anchor="mm")
        rows = self.lines[-ROWS:]
        y = TITLE_H + PAD_Y
        for idx, (text, kind) in enumerate(rows):
            x = PAD_X
            if kind == "cmd":
                d.text((x, y), "$ ", font=FB, fill=GREEN)
                x += CW * 2
            elif kind == "cont":
                x += CW * 2
            d.text((x, y), text, font=FB if kind == "banner" else F, fill=colour_for(text, kind))
            if cursor and idx == len(rows) - 1:
                cx = x + F.getlength(text)
                d.rectangle([cx + 2, y + 2, cx + CW, y + LH - 4], fill=FG)
            y += LH
        return img.tobytes()

    def hold(self, seconds, cursor=False):
        frame = self.draw(cursor)
        for _ in range(max(1, int(round(seconds * FPS)))):
            self.proc.stdin.write(frame)
            self.frames += 1

    def close(self):
        self.proc.stdin.close()
        self.proc.wait()


def main():
    scene_path, workdir = sys.argv[1], sys.argv[2]
    scene = json.load(open(scene_path, encoding="utf-8"))
    root = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    os.makedirs(workdir, exist_ok=True)

    env = dict(os.environ, TERM="dumb", NO_COLOR="1")
    for k, v in (scene.get("env") or {}).items():
        if isinstance(v, str) and v.startswith("$file:"):
            v = open(os.path.join(root, v[6:]), encoding="utf-8").read().strip()
        env[k] = str(v)

    scr = Screen(scene.get("title", "meridian-mutual: workshop"))
    scr.start(os.path.join(workdir, "raw.mp4"))
    beats = []
    scr.hold(0.6)

    for i, step in enumerate(scene["steps"], 1):
        if "beat" in step:
            beats.append((scr.now(), step["beat"]))
        if "banner" in step:
            for line in wrap(step["banner"]):
                scr.lines.append((line, "banner"))
            scr.hold(step.get("hold", 0.8))
        if step.get("clear"):
            scr.lines = []
            scr.hold(0.3)
        if "show" in step:
            cmd = step["show"]
            width = COLS - 2
            parts = [cmd[j:j + width] for j in range(0, len(cmd), width)] or [""]
            for n, part in enumerate(parts):          # type it, a few characters per frame
                scr.lines.append(("", "cmd" if n == 0 else "cont"))
                for j in range(0, len(part) + 1, 3):
                    scr.lines[-1] = (part[:j], scr.lines[-1][1])
                    scr.hold(1 / FPS, cursor=True)
                scr.lines[-1] = (part, scr.lines[-1][1])
            scr.hold(0.5, cursor=True)
            t0 = time.time()
            res = subprocess.run(["bash", "-c", cmd], cwd=root, env=env, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, text=True, timeout=step.get("timeout", 180))
            took = time.time() - t0
            out = ANSI.sub("", res.stdout).rstrip("\n")
            if res.returncode not in step.get("ok_exit", [0]):
                scr.close()
                sys.exit(f"TAKE FAILED: step {i} exited {res.returncode}: {cmd}\n{out[-800:]}")
            for forbidden in step.get("must_show", []):
                if forbidden not in out:
                    scr.close()
                    sys.exit(f"TAKE FAILED: step {i} output does not contain {forbidden!r}\n{out[-800:]}")
            scr.hold(min(1.2, max(0.2, took)))        # the real wait, capped
            lines = wrap(out) if out else []
            per = min(0.12, 2.2 / max(1, len(lines)))  # output scrolls in, quickly for long output
            for line in lines:
                scr.lines.append((line, "out"))
                scr.hold(per)
            scr.lines.append(("", "out"))
        if "pause" in step:
            scr.hold(step["pause"])

    beats.append((scr.now(), "done"))
    scr.hold(0.8)
    scr.close()
    with open(os.path.join(workdir, "beats.tsv"), "w", encoding="utf-8") as f:
        f.write("# seconds\tbeat\n")
        for t, name in beats:
            f.write(f"{t:.3f}\t{name}\n")
    print(f"recorded {os.path.join(workdir, 'raw.mp4')} with {len(beats)} beats")


if __name__ == "__main__":
    main()
