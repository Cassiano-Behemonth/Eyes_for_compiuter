"""
Eye — Servidor e Launcher do Protetor de Tela para Windows
Com rastreador de presença e rosto via OpenCV / Webcam em tempo real
"""

import os
import sys
import json
import time
import threading
import subprocess
import webbrowser
import atexit
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
WEB_DIR = os.path.join(BASE_DIR, "web")
TEMAS_DIR = os.path.join(BASE_DIR, "Temas")
EXEMPLOS_DIR = os.path.join(BASE_DIR, "Exemplos", "Temas")

os.makedirs(TEMAS_DIR, exist_ok=True)

def launch_browser(url):
    """Abre o Microsoft Edge em modo kiosk de tela cheia ou navegador padrão"""
    edge_paths = [
        os.path.expandvars(r"%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"),
        os.path.expandvars(r"%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"),
        os.path.expandvars(r"%LocalAppData%\Microsoft\Edge\Application\msedge.exe")
    ]
    temp_profile = os.path.join(os.environ.get("TEMP", "C:\\Temp"), "EyeEdgeKioskProfile")

    for p in edge_paths:
        if os.path.exists(p):
            cmd = [
                p,
                f"--user-data-dir={temp_profile}",
                "--no-first-run",
                "--no-default-browser-check",
                f"--app={url}",
                "--start-fullscreen"
            ]
            try:
                subprocess.Popen(cmd)
                return
            except Exception as e:
                print(f"[!] Erro ao abrir Edge: {e}")

    try:
        webbrowser.open(url)
    except Exception:
        pass

# Trava de instância única para evitar múltiplos processos competindo pela webcam
LOCK_FILE_PATH = os.path.join(BASE_DIR, ".eye_instance.lock")
lock_file_handle = None
try:
    import msvcrt
    lock_file_handle = open(LOCK_FILE_PATH, "w")
    msvcrt.locking(lock_file_handle.fileno(), msvcrt.LK_NBLCK, 1)
    lock_file_handle.write(str(os.getpid()))
    lock_file_handle.flush()
except (ImportError, OSError):
    print("[*] Servidor Eye já está em execução.")
    if "--no-browser" not in sys.argv:
        launch_browser("http://127.0.0.1:54321")
    sys.exit(0)

# ================= RASTREADOR DE WEBCAM (OPENCV) =================

class WebcamPresenceTracker:
    def __init__(self):
        self.lock = threading.Lock()
        self.running = False
        self.cap = None
        self.active_backend = None
        self.cascade_alt2 = None
        self.cascade_default = None
        self.cascade_alt = None
        self.cascade_profile = None
        self.clahe = None
        self.last_jpeg = None
        self.smoothed_x = 0.0
        self.smoothed_y = 0.0
        self.smoothed_closeness = 0.0
        self.last_seen_time = 0.0
        self.current_presence = {
            "detected": False,
            "x": 0.0,
            "y": 0.0,
            "closeness": 0.0,
            "camera_active": False,
            "timestamp": time.time(),
            "mean_brightness": 0.0,
            "backend": "none"
        }
        self.debug_info = {}
        self.thread = None

    def start(self):
        if self.running:
            return
        self.running = True
        # Toda inicialização da câmera roda DENTRO da thread de captura para evitar
        # problemas de COM Single Threaded Apartment (STA/MTA) no Windows.
        self.thread = threading.Thread(target=self._loop, daemon=True)
        self.thread.start()

    def stop(self):
        self.running = False
        if self.thread and self.thread.is_alive():
            self.thread.join(timeout=1.0)
        self._release_camera()

    def _release_camera(self):
        if self.cap:
            try:
                self.cap.release()
            except Exception:
                pass
            self.cap = None

    def _init_cascades(self):
        import cv2
        if self.cascade_alt2 is None:
            self.cascade_alt2 = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_alt2.xml')
            self.cascade_default = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')
            self.cascade_alt = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_alt.xml')
            self.cascade_profile = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_profileface.xml')
            self.clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))

    def _init_camera(self):
        import cv2
        import numpy as np
        self._init_cascades()
        self._release_camera()

        # No Windows, CAP_DSHOW é o padrão DirectShow mais estável para webcams USB.
        # Evitamos CAP_MSMF pois gera erros assíncronos -2147483638 em muitos drivers.
        candidate_backends = [
            ("DSHOW", cv2.CAP_DSHOW),
            ("ANY", cv2.CAP_ANY)
        ]

        for attempt in range(2):
            for b_name, b_val in candidate_backends:
                cap = None
                try:
                    cap = cv2.VideoCapture(0, b_val)
                    if not cap or not cap.isOpened():
                        if cap:
                            cap.release()
                        continue

                    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
                    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
                    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

                    # Warmup de até 15 quadros para o AGC / autoexposição estabilizar
                    mean_val = 0.0
                    for _ in range(15):
                        ret, test_frame = cap.read()
                        if ret and test_frame is not None:
                            m = float(np.mean(test_frame))
                            if m > mean_val:
                                mean_val = m
                            if mean_val > 5.0:
                                break
                        time.sleep(0.04)

                    if mean_val > 5.0:
                        self.cap = cap
                        self.active_backend = b_name
                        with self.lock:
                            self.current_presence["camera_active"] = True
                            self.current_presence["backend"] = b_name
                            self.current_presence["mean_brightness"] = round(mean_val, 1)
                        print(f"[OK] Webcam conectada com sucesso via {b_name} (brilho médio={mean_val:.1f})", flush=True)
                        return True
                    else:
                        cap.release()
                except Exception as e:
                    print(f"[!] Erro ao testar backend {b_name}: {e}", flush=True)
                    if cap:
                        try:
                            cap.release()
                        except Exception:
                            pass
            time.sleep(0.3)

        # Fallback se nenhum retornou brilho > 5.0
        for b_name, b_val in candidate_backends:
            try:
                cap = cv2.VideoCapture(0, b_val)
                if cap and cap.isOpened():
                    self.cap = cap
                    self.active_backend = b_name
                    with self.lock:
                        self.current_presence["camera_active"] = True
                        self.current_presence["backend"] = b_name
                        self.current_presence["mean_brightness"] = 0.0
                    print(f"[INFO] Webcam aberta via {b_name} (modo fallback).", flush=True)
                    return True
            except Exception:
                pass

        with self.lock:
            self.current_presence["camera_active"] = False
            self.current_presence["detected"] = False
        print("[!] Nenhuma webcam funcional encontrada no momento.", flush=True)
        return False

    def _loop(self):
        import cv2
        import numpy as np

        self._init_camera()

        last_check = 0.0
        consecutive_failures = 0
        black_frame_count = 0

        while self.running:
            if not self.cap or not self.cap.isOpened():
                time.sleep(1.0)
                if self.running:
                    self._init_camera()
                continue

            ret, frame = self.cap.read()
            if not ret or frame is None:
                consecutive_failures += 1
                if consecutive_failures >= 20:
                    print("[!] Webcam desconectou ou sem sinal. Tentando reconectar...")
                    self._init_camera()
                    consecutive_failures = 0
                time.sleep(0.04)
                continue

            consecutive_failures = 0
            mean_b = float(np.mean(frame))

            # Se todos os pixels forem zero de forma persistente, tenta reiniciar
            if mean_b < 1.0:
                black_frame_count += 1
                if black_frame_count >= 30:
                    print("[!] Quadro preto persistente detectado. Reinicializando câmera...")
                    self._init_camera()
                    black_frame_count = 0
                    time.sleep(0.5)
                    continue
            else:
                black_frame_count = 0

            now = time.time()
            if now - last_check >= 0.033:  # ~30 FPS
                last_check = now
                h, w = frame.shape[:2]
                gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

                scale_w = 320.0 / w
                scale_h = 240.0 / h
                small_gray = cv2.resize(gray, (320, 240))
                clahe_small = self.clahe.apply(small_gray)

                # Ensemble de detecção: frontal + perfil (ambos os lados)
                faces = self.cascade_alt2.detectMultiScale(clahe_small, scaleFactor=1.1, minNeighbors=3, minSize=(22, 22))
                if len(faces) == 0:
                    faces = self.cascade_default.detectMultiScale(clahe_small, scaleFactor=1.1, minNeighbors=3, minSize=(22, 22))
                if len(faces) == 0:
                    faces = self.cascade_alt.detectMultiScale(clahe_small, scaleFactor=1.1, minNeighbors=3, minSize=(22, 22))
                if len(faces) == 0:
                    faces = self.cascade_profile.detectMultiScale(clahe_small, scaleFactor=1.1, minNeighbors=3, minSize=(22, 22))
                if len(faces) == 0:
                    flipped_small = cv2.flip(clahe_small, 1)
                    flip_faces = self.cascade_profile.detectMultiScale(flipped_small, scaleFactor=1.1, minNeighbors=3, minSize=(22, 22))
                    if len(flip_faces) > 0:
                        faces = []
                        for (fx_f, fy_f, fw_f, fh_f) in flip_faces:
                            faces.append((320 - fx_f - fw_f, fy_f, fw_f, fh_f))

                with self.lock:
                    self.debug_info = {
                        "ret": ret,
                        "shape": list(frame.shape),
                        "mean": round(mean_b, 2),
                        "faces_found": len(faces),
                        "backend": self.active_backend
                    }

                display_frame = frame.copy()

                if len(faces) > 0:
                    largest_face = max(faces, key=lambda f: f[2] * f[3])
                    sfx, sfy, sfw, sfh = largest_face

                    fx = int(sfx / scale_w)
                    fy = int(sfy / scale_h)
                    fw = int(sfw / scale_w)
                    fh = int(sfh / scale_h)

                    cx = fx + fw / 2.0
                    cy = fy + fh / 2.0

                    # Mirrored normalizado: se a pessoa vai para a sua direita, o olho olha para a direita
                    target_x = (1.0 - (cx / w) - 0.5) * 2.4
                    target_y = ((cy / h) - 0.5) * 2.4
                    target_close = max(0.0, min(1.0, (fw / w - 0.10) / 0.32))

                    self.smoothed_x += (target_x - self.smoothed_x) * 0.40
                    self.smoothed_y += (target_y - self.smoothed_y) * 0.40
                    self.smoothed_closeness += (target_close - self.smoothed_closeness) * 0.30
                    self.last_seen_time = now

                    cv2.rectangle(display_frame, (fx, fy), (fx + fw, fy + fh), (0, 255, 120), 2)
                    cv2.putText(display_frame, f"ROSTO [{round(float(self.smoothed_x), 2)}, {round(float(self.smoothed_y), 2)}]",
                                (fx, max(22, fy - 8)), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 255, 120), 1)

                    with self.lock:
                        self.current_presence = {
                            "detected": True,
                            "x": round(float(self.smoothed_x), 3),
                            "y": round(float(self.smoothed_y), 3),
                            "closeness": round(float(self.smoothed_closeness), 3),
                            "camera_active": True,
                            "timestamp": now,
                            "mean_brightness": round(mean_b, 1),
                            "backend": self.active_backend
                        }
                else:
                    is_still_present = (now - self.last_seen_time < 1.2)
                    with self.lock:
                        self.current_presence["detected"] = is_still_present
                        self.current_presence["timestamp"] = now
                        self.current_presence["mean_brightness"] = round(mean_b, 1)

                _, jpeg_bytes = cv2.imencode('.jpg', cv2.resize(display_frame, (320, 240)), [cv2.IMWRITE_JPEG_QUALITY, 70])
                with self.lock:
                    self.last_jpeg = jpeg_bytes.tobytes()

            time.sleep(0.015)

        self._release_camera()

    def get_presence(self):
        with self.lock:
            return dict(self.current_presence)

    def get_last_jpeg(self):
        with self.lock:
            return self.last_jpeg

    def get_debug_info(self):
        with self.lock:
            return dict(self.debug_info)

tracker = WebcamPresenceTracker()
tracker.start()
atexit.register(tracker.stop)


# ================= TEMAS =================

def scan_user_themes():
    themes = {}
    search_dirs = [TEMAS_DIR]
    if os.path.exists(EXEMPLOS_DIR):
        search_dirs.append(EXEMPLOS_DIR)

    for base in search_dirs:
        if not os.path.exists(base):
            continue
        for entry in os.listdir(base):
            folder = os.path.join(base, entry)
            if not os.path.isdir(folder):
                continue

            theme_name = entry
            json_file = os.path.join(folder, "tema.json")
            theme_data = {}
            if os.path.exists(json_file):
                try:
                    with open(json_file, "r", encoding="utf-8") as f:
                        theme_data = json.load(f)
                except Exception as e:
                    print(f"[!] Erro ao ler {json_file}: {e}")

            for img_name, prop in [("iris.png", "irisImage"), ("esclera.png", "scleraImage"), ("pele.png", "skinImage")]:
                img_path = os.path.join(folder, img_name)
                if os.path.exists(img_path):
                    rel_url = f"/temas_files/{entry}/{img_name}"
                    theme_data[prop] = rel_url

            if theme_data or os.path.exists(os.path.join(folder, "iris.png")):
                theme_data["name"] = theme_name
                themes[theme_name] = theme_data

    return themes


# ================= SERVIDOR HTTP =================

class EyeRequestHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)

    def log_message(self, format, *args):
        # O status 200 indica sucesso em HTTP, mas milhares de requisições por minuto
        # no terminal poluem a tela e parecem um loop de erro. Filtramos aqui:
        if len(args) >= 2 and str(args[1]) in ("200", "304"):
            return
        super().log_message(format, *args)

    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

    def do_GET(self):
        clean_path = self.path.split("?")[0]

        if clean_path == "/api/presence":
            pres = tracker.get_presence()
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
            self.send_header("Pragma", "no-cache")
            self.send_header("Expires", "0")
            self.end_headers()
            self.wfile.write(json.dumps(pres).encode("utf-8"))
            return

        if clean_path == "/api/presence_stream":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
            self.send_header("Connection", "keep-alive")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            try:
                while True:
                    pres = tracker.get_presence()
                    msg = f"data: {json.dumps(pres)}\n\n"
                    self.wfile.write(msg.encode("utf-8"))
                    self.wfile.flush()
                    time.sleep(0.04)
            except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError, OSError):
                pass
            return

        if clean_path == "/api/debug_cam":
            dbg = tracker.get_debug_info()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-cache, no-store")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps(dbg).encode())
            return

        if clean_path == "/api/camera_snapshot":
            jpeg = tracker.get_last_jpeg()
            if jpeg:
                self.send_response(200)
                self.send_header("Content-Type", "image/jpeg")
                self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(jpeg)
            else:
                self.send_response(503)
                self.end_headers()
            return

        if clean_path == "/api/camera_feed":
            self.send_response(200)
            self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            try:
                while True:
                    jpeg = tracker.get_last_jpeg()
                    if jpeg:
                        self.wfile.write(b"--frame\r\nContent-Type: image/jpeg\r\n\r\n" + jpeg + b"\r\n")
                        self.wfile.flush()
                    time.sleep(0.05)
            except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError, OSError):
                pass
            return

        if clean_path == "/api/temas":
            themes = scan_user_themes()
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps(themes, ensure_ascii=False).encode("utf-8"))
            return

        if self.path.startswith("/temas_files/"):
            parts = self.path[len("/temas_files/"):].split("/")
            if len(parts) >= 2:
                folder_name = parts[0]
                file_name = parts[1]
                file_path = os.path.join(TEMAS_DIR, folder_name, file_name)
                if not os.path.exists(file_path):
                    file_path = os.path.join(EXEMPLOS_DIR, folder_name, file_name)

                if os.path.exists(file_path):
                    self.send_response(200)
                    if file_name.endswith(".png"):
                        self.send_header("Content-Type", "image/png")
                    elif file_name.endswith(".json"):
                        self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    with open(file_path, "rb") as f:
                        self.wfile.write(f.read())
                    return

        return super().do_GET()

    def do_POST(self):
        if self.path == "/api/abrir-pasta":
            try:
                os.startfile(TEMAS_DIR)
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(b'{"status":"ok"}')
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(str(e).encode())
            return

        self.send_response(404)
        self.end_headers()




def main():
    port = 54321
    server = None
    for p in range(54321, 54345):
        try:
            server = ThreadingHTTPServer(("127.0.0.1", p), EyeRequestHandler)
            port = p
            break
        except OSError:
            continue

    if not server:
        print("[!] Não foi possível iniciar o servidor HTTP.")
        sys.exit(1)

    url = f"http://127.0.0.1:{port}"
    print(f"=====================================================")
    print(f"  Eye — Protetor de Tela Windows")
    print(f"  URL: {url}")
    print(f"  Sensor de Webcam: Ativo e calibrado")
    print(f"  Pasta de Temas: {TEMAS_DIR}")
    print(f"=====================================================")

    # Abre navegador se chamado diretamente
    if "--no-browser" not in sys.argv:
        launch_browser(url)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[+] Encerrando Eye...")
        tracker.stop()
        server.server_close()


if __name__ == "__main__":
    main()
