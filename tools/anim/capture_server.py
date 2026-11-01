# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""Serveur local entre Studio et le disque (Windows, 127.0.0.1:34991).

GET  /frames        sert le fichier JSON de poses donné en argument
GET  /shot?name=X   capture la fenêtre Studio dans <dossier>/X.png, sans jeton ni clic (fenêtre non réduite)
POST /save?path=P   écrit un .rbxm reçu en hexadécimal sous assets/rbx/ (P relatif à la racine du dépôt)
GET  /quit          arrête le serveur

Usage, depuis la racine du worktree : uv run tools/anim/capture_server.py <dossier_captures> <frames.json>
"""

import ctypes
import ctypes.wintypes as W
import json
import os
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

from PIL import Image

OUT, DATA = sys.argv[1], sys.argv[2]
u32, g32 = ctypes.windll.user32, ctypes.windll.gdi32
u32.SetProcessDPIAware()


# Cette méthode permet de trouver la fenêtre principale de Studio d'après son titre.
def find_window():
	found = []

	def on_window(handle, _):
		size = u32.GetWindowTextLengthW(handle)
		title = ctypes.create_unicode_buffer(size + 1)
		u32.GetWindowTextW(handle, title, size + 1)
		if u32.IsWindowVisible(handle) and "Roblox Studio" in title.value:
			found.append((handle, title.value))
		return True

	u32.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, W.HWND, W.LPARAM)(on_window), 0)
	return found


# Cette méthode permet de copier le contenu de la fenêtre Studio dans une image, même si elle est partiellement couverte.
def grab(handle):
	rect = W.RECT()
	u32.GetWindowRect(handle, ctypes.byref(rect))
	width, height = rect.right - rect.left, rect.bottom - rect.top
	dc = u32.GetWindowDC(handle)
	mem = g32.CreateCompatibleDC(dc)
	bitmap = g32.CreateCompatibleBitmap(dc, width, height)
	g32.SelectObject(mem, bitmap)
	ok = u32.PrintWindow(handle, mem, 2)

	class BitmapInfo(ctypes.Structure):
		_fields_ = [
			("size", W.DWORD),
			("width", W.LONG),
			("height", W.LONG),
			("planes", W.WORD),
			("bits", W.WORD),
			("compression", W.DWORD),
			("image_size", W.DWORD),
			("x_ppm", W.LONG),
			("y_ppm", W.LONG),
			("used", W.DWORD),
			("important", W.DWORD),
		]

	info = BitmapInfo(ctypes.sizeof(BitmapInfo), width, -height, 1, 32, 0, 0, 0, 0, 0, 0)
	buffer = ctypes.create_string_buffer(width * height * 4)
	g32.GetDIBits(mem, bitmap, 0, height, buffer, ctypes.byref(info), 0)
	g32.DeleteObject(bitmap)
	g32.DeleteDC(mem)
	u32.ReleaseDC(handle, dc)
	return ok, Image.frombuffer("RGB", (width, height), buffer, "raw", "BGRX", 0, 1)


class Handler(BaseHTTPRequestHandler):
	def log_message(self, *args):
		pass

	# Cette méthode permet de répondre à une requête avec un corps et un code HTTP.
	def reply(self, body, code=200):
		self.send_response(code)
		self.send_header("Content-Length", str(len(body)))
		self.end_headers()
		self.wfile.write(body)

	# Cette méthode permet de servir les poses, de capturer la fenêtre Studio ou d'arrêter le serveur.
	def do_GET(self):
		url = urllib.parse.urlparse(self.path)
		query = urllib.parse.parse_qs(url.query)
		if url.path == "/frames":
			with open(DATA, "rb") as fh:
				return self.reply(fh.read())
		if url.path == "/shot":
			windows = find_window()
			if not windows:
				return self.reply(b"fenetre Studio introuvable", 500)
			ok, image = grab(windows[0][0])
			image.save(os.path.join(OUT, query["name"][0] + ".png"))
			return self.reply(json.dumps({"ok": ok, "size": image.size, "title": windows[0][1]}).encode())
		if url.path == "/quit":
			self.reply(b"bye")
			os._exit(0)
		self.reply(b"?", 404)

	# Cette méthode permet d'écrire un seul .rbxm reçu de Studio, sans réécrire les autres armes comme l'export complet.
	def do_POST(self):
		url = urllib.parse.urlparse(self.path)
		path = urllib.parse.parse_qs(url.query).get("path", [""])[0]
		length = int(self.headers.get("Content-Length", 0))
		body = self.rfile.read(length)
		normal = os.path.normpath(path).replace("\\", "/")
		if url.path != "/save" or not normal.startswith("assets/rbx/") or not normal.endswith(".rbxm"):
			return self.reply(b"chemin refuse", 400)
		with open(normal, "wb") as fh:
			fh.write(bytes.fromhex(body.decode()))
		self.reply(normal.encode())


HTTPServer(("127.0.0.1", 34991), Handler).serve_forever()
