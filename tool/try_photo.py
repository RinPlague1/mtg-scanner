"""Run the dark-card edge refiner on your own photos, no phone build needed.

    pip install numpy opencv-python
    python try_photo.py my_card.jpg [more.jpg ...]

Take portrait photos with the card roughly centred and filling ~78% of the
width (as the app's guide asks). For each photo this writes <name>_debug.png
showing the guide (white), the detected card (green), and the title and
collector-line crops that would go to OCR.

refine_mirror.py is a line-for-line Python mirror of lib/vision/edge_refiner.dart,
so tuning done here (band, thresholds) carries straight over to the app.
"""
import sys
import cv2
import numpy as np
from refine_mirror import refine, quad_from_lines

NAME = (0.035, 0.010, 0.80, 0.125)
SETLINE = (-0.03, 0.895, 0.52, 1.04)


def guide_box(aspect_wh, wf=0.78, cy=0.46):
    h = wf / (63 / 88) * aspect_wh
    w = wf
    if h > 0.9:
        w, h = wf * 0.9 / h, 0.9
    left = (1 - w) / 2
    top = max(cy - h / 2, 0.02)
    return (left, top, left + w, top + h)


def crop(img, quad, region, out_w):
    u0, v0, u1, v1 = region
    out_h = max(8, int(round(out_w / ((u1 - u0) * 63 / 88 / (v1 - v0)))))
    q = np.array(quad, np.float32)
    uu, vv = np.meshgrid(u0 + (u1 - u0) * (np.arange(out_w) + .5) / out_w,
                         v0 + (v1 - v0) * (np.arange(out_h) + .5) / out_h)
    w = [(1 - uu) * (1 - vv), uu * (1 - vv), uu * vv, (1 - uu) * vv]
    mx = sum(w[i] * q[i, 0] for i in range(4)).astype(np.float32)
    my = sum(w[i] * q[i, 1] for i in range(4)).astype(np.float32)
    return cv2.remap(img, mx, my, cv2.INTER_LINEAR)


def main(paths):
    for p in paths:
        bgr = cv2.imread(p)
        if bgr is None:
            print('cannot read', p)
            continue
        h, w = bgr.shape[:2]
        if w > h:
            bgr = cv2.rotate(bgr, cv2.ROTATE_90_CLOCKWISE)
            h, w = w, h
        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        step = max(1, w // 360)
        small = rgb[step // 2::step, step // 2::step][: h // step, : w // step]
        guide = guide_box(w / h)
        lines = refine(small, guide)
        quad = np.array(quad_from_lines(lines, guide, small.shape[1], small.shape[0])) * step + step / 2
        found = [k for k, v in lines.items() if v]
        dbg = bgr.copy()
        g = np.array(guide) * [w, h, w, h]
        cv2.rectangle(dbg, (int(g[0]), int(g[1])), (int(g[2]), int(g[3])), (255, 255, 255), 2)
        cv2.polylines(dbg, [quad.astype(np.int32)], True, (0, 255, 0), 3)
        name = crop(bgr, quad, NAME, 640)
        setl = crop(bgr, quad, SETLINE, 720)
        scale = 640 / w
        panel = cv2.resize(dbg, (640, int(h * scale)))
        out = np.vstack([panel, np.full((8, 640, 3), 80, np.uint8), name,
                         np.full((8, 640, 3), 80, np.uint8), cv2.resize(setl, (640, int(setl.shape[0] * 640 / 720)))])
        dst = p.rsplit('.', 1)[0] + '_debug.png'
        cv2.imwrite(dst, out)
        print(f'{p}: sides locked {found} -> {dst}')


if __name__ == '__main__':
    main(sys.argv[1:] or sys.exit(__doc__))
