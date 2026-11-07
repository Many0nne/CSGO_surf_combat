# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow", "imageio-ffmpeg"]
# ///
"""Assemble les images d'une animation de mirrors.py en MP4, avec la maquette d'interface posée sur chaque image.

Usage : uv run tools/menu/video.py <Oswald .ttf> <dossier des images f_*.png> <sortie.mp4>
ffmpeg vient du paquet imageio-ffmpeg : rien à installer sur le poste.
"""
import glob, os, subprocess, sys, tempfile

import imageio_ffmpeg

HERE = os.path.dirname(os.path.abspath(__file__))


# Cette méthode permet d'habiller chaque image avec l'interface puis d'encoder la vidéo à 24 images/s.
def main():
    font, frames, out = sys.argv[1], sys.argv[2], sys.argv[3]
    src = sorted(glob.glob(os.path.join(frames, "f_*.png")))
    with tempfile.TemporaryDirectory() as tmp:
        for i, f in enumerate(src):
            subprocess.run([sys.executable, os.path.join(HERE, "overlay_mockup.py"), font, f, os.path.join(tmp, "%04d.jpg" % i), "dark"], check=True)
        ff = imageio_ffmpeg.get_ffmpeg_exe()
        subprocess.run([ff, "-y", "-framerate", "24", "-i", os.path.join(tmp, "%04d.jpg"), "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", out], check=True, capture_output=True)
    print(out, len(src), "images")


if __name__ == "__main__":
    main()
