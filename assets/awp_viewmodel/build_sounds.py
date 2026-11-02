"""Découpe les sons de l'AWP depuis leurs sources et harmonise leur niveau (issue #52).

Usage : uv run --no-project --with numpy --with soundfile python assets/awp_viewmodel/build_sounds.py <sources> <sortie>
Chaque fichier produit contient un seul événement, avec l'attaque au tout début : le calage vient des marqueurs
d'animation, pas du fichier. Pour les sources, voir SOURCES. Les temps de CUTS sont ceux de ces fichiers.
"""

import pathlib
import sys

import numpy as np
import soundfile as sf

# Nom de fichier dans <sources> -> origine. Les aperçus MP3 Freesound (-hq) suffisent, seule source validée à l'écoute.
# Licence Pixabay : Shoot et Bolt, publiés sur Roblox, ne sont pas versionnés (pas de redistribution du son seul).
SOURCES = {
    "reference.mp3": "https://pixabay.com/sound-effects/film-special-effects-sniper-rifle-129927/ (Pixabay)",
    "clips.mp3": "https://cdn.freesound.org/previews/725/725403_7157894-hq.mp3 (CC0)",
    "draw.mp3": "https://cdn.freesound.org/previews/272/272394_4783367-hq.mp3 (CC0)",
    "zoom.mp3": "https://cdn.freesound.org/previews/210/210018_3051019-hq.mp3 (CC0)",
}

# Sortie -> (source, début en s, fin en s, inverser).
CUTS = {
    "Shoot": ("reference.mp3", 1.99, 3.82, False),
    "Bolt": ("reference.mp3", 0.44, 1.42, False),
    "ClipOut": ("clips.mp3", 1.72, 2.05, False),
    "ClipIn": ("clips.mp3", 11.70, 11.97, False),
    "ClipHit": ("clips.mp3", 18.81, 18.95, False),
    "Draw": ("draw.mp3", 1.07, 1.41, False),
    "ZoomIn": ("zoom.mp3", 0.0, 0.226, False),
    "ZoomOut": ("zoom.mp3", 0.0, 0.226, True),
}

ONSET_DB = -30.0  # l'attaque commence au premier échantillon à ce niveau sous le pic de l'extrait
TAIL_DB = -60.0  # la fin de l'extrait est coupée sous ce niveau, relatif au pic
PRE_ROLL_S = 0.001
FADE_IN_S = 0.001
FADE_OUT_S = 0.02
TARGET_RMS_DB = -12.0  # niveau court terme visé (fenêtre de 50 ms)
PEAK_LIMIT_DB = -1.0


def db_to_linear(value):
    """Cette méthode permet de convertir un niveau en dB en gain linéaire lorsqu'un seuil est comparé au signal."""
    return 10 ** (value / 20)


def trim(audio, sample_rate):
    """Cette méthode permet de placer l'attaque au tout début lorsqu'un extrait commence par du silence ou du bruit.
    Elle coupe aussi la fin passée sous le seuil de queue et ajoute de courts fondus pour éviter un clic."""
    level = np.abs(audio).max(axis=1)
    peak = level.max()
    start = int(np.argmax(level >= peak * db_to_linear(ONSET_DB)))
    start = max(0, start - int(PRE_ROLL_S * sample_rate))
    above = np.nonzero(level >= peak * db_to_linear(TAIL_DB))[0]
    end = int(above[-1]) + 1
    audio = audio[start:end].copy()
    fade_in = min(len(audio), int(FADE_IN_S * sample_rate))
    fade_out = min(len(audio), int(FADE_OUT_S * sample_rate))
    audio[:fade_in] *= np.linspace(0, 1, fade_in)[:, None]
    audio[-fade_out:] *= np.linspace(1, 0, fade_out)[:, None]
    return audio


def normalize(audio, sample_rate):
    """Cette méthode permet de donner le même niveau perçu à chaque son lorsque Sound.Volume doit seul régler le mélange.
    Le gain vise un niveau court terme, puis il est limité pour que le pic ne sature pas."""
    mono = audio.mean(axis=1)
    window = max(1, int(0.05 * sample_rate))
    energy = np.convolve(mono**2, np.ones(window) / window, mode="same")
    rms = np.sqrt(energy.max())
    gain = db_to_linear(TARGET_RMS_DB) / max(rms, 1e-9)
    return audio * min(gain, db_to_linear(PEAK_LIMIT_DB) / np.abs(audio).max())


def build(source_dir, output_dir):
    """Cette méthode permet de produire tous les extraits lorsque les sources ou la table CUTS changent."""
    output_dir.mkdir(parents=True, exist_ok=True)
    for name, (source, start, end, reverse) in CUTS.items():
        audio, sample_rate = sf.read(source_dir / source, always_2d=True)
        cut = audio[int(start * sample_rate) : int(end * sample_rate)]
        if reverse:
            cut = cut[::-1]
        result = normalize(trim(cut, sample_rate), sample_rate)
        sf.write(output_dir / f"{name}.wav", result, sample_rate, subtype="PCM_16")
        peak = 20 * np.log10(np.abs(result).max())
        print(f"{name:10} {len(result) / sample_rate:5.3f} s  {sample_rate} Hz  {result.shape[1]} can.  pic {peak:5.1f} dB")


if __name__ == "__main__":
    build(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]))
