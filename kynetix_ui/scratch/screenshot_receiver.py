import socket
import os
import sys

TARGET_DIR = r"C:\Users\Dhruv\.gemini\antigravity-ide\brain\a5fbb340-2e0b-4e19-afe0-161ed383b353"
os.makedirs(TARGET_DIR, exist_ok=True)

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(('0.0.0.0', 9876))
server.listen(5)
server.settimeout(180.0)

print("[RECEIVER] Listening on port 9876...")
received_count = 0

try:
    while received_count < 6:
        conn, addr = server.accept()
        with conn:
            # Read header line
            header = b""
            while b"\n" not in header:
                chunk = conn.recv(1)
                if not chunk:
                    break
                header += chunk
            
            header_str = header.decode('utf-8').strip()
            if ":" not in header_str:
                continue
            name, size_str = header_str.split(":", 1)
            total_size = int(size_str)
            
            data = b""
            while len(data) < total_size:
                packet = conn.recv(min(65536, total_size - len(data)))
                if not packet:
                    break
                data += packet
            
            filepath = os.path.join(TARGET_DIR, f"{name}.png")
            with open(filepath, "wb") as f:
                f.write(data)
            
            received_count += 1
            print(f"[RECEIVER] ({received_count}/6) Saved {filepath} ({len(data)} bytes)")
except socket.timeout:
    print("[RECEIVER] Timeout waiting for screenshots.")
finally:
    server.close()
    print(f"[RECEIVER] Done. Total screenshots captured: {received_count}")
