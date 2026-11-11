"""Construit les animations et le rig du Ka-Bar sans toucher au Blender ouvert (écrit assets/kabar_viewmodel/export/).

  blender -b --factory-startup --python assets/kabar_viewmodel/run_build.py
"""

import os

D = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(D, "build_viewmodel.py"), encoding="utf-8") as fh:
	exec(fh.read(), {"__name__": "__main__", "ASSET_DIR": D})
