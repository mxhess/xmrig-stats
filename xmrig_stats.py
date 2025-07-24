import http.server
import socketserver
import json
import redis
import requests
import threading
import time
from urllib.parse import urlparse

# Configuration
PROXY_HOST = "127.0.0.1"
PROXY_PORT = 8080
ACCESS_TOKEN = ""  # Set if required
VALKEY_HOST = "localhost"
VALKEY_PORT = 6379
UPDATE_INTERVAL = 5  # Seconds
DATA_TTL = 3 * 60 * 60  # 3 hours in seconds
HTTP_PORT = 8282  # Changed to avoid Docker Proxy conflict

# Valkey keys (same as Redis keys, as Valkey is compatible)
SUMMARY_KEY = "xmrig:summary"
WORKERS_KEY = "xmrig:workers"
MINERS_KEY = "xmrig:miners"
HASHRATE_HISTORY_KEY = "xmrig:hashrate_history"

# Initialize Valkey client (using redis-py, compatible with Valkey)
try:
    valkey_client = redis.Redis(host=VALKEY_HOST, port=VALKEY_PORT, decode_responses=True)
    valkey_client.ping()  # Test connection
    print("Connected to Valkey successfully")
except redis.ConnectionError as e:
    print(f"Failed to connect to Valkey at {VALKEY_HOST}:{VALKEY_PORT}: {e}")
    print("Ensure Valkey is running and the host/port are correct.")
    exit(1)

# Function to fetch and store stats
def fetch_and_store_stats():
    headers = {"Authorization": f"Bearer {ACCESS_TOKEN}"} if ACCESS_TOKEN else {}
    base_url = f"http://{PROXY_HOST}:{PROXY_PORT}"

    while True:
        try:
            timestamp = int(time.time())

            # Fetch summary
            response = requests.get(f"{base_url}/1/summary", headers=headers, timeout=5)
            response.raise_for_status()
            summary = response.json()
            valkey_client.setex(SUMMARY_KEY, DATA_TTL, json.dumps(summary))

            # Store hashrate
            hashrate = summary.get("hashrate", {}).get("total", [0])[0] or 0
            valkey_client.zadd(HASHRATE_HISTORY_KEY, {str(hashrate): timestamp})
            valkey_client.expire(HASHRATE_HISTORY_KEY, DATA_TTL)
            valkey_client.zremrangebyscore(HASHRATE_HISTORY_KEY, 0, timestamp - DATA_TTL)

            # Fetch workers
            response = requests.get(f"{base_url}/1/workers", headers=headers, timeout=5)
            response.raise_for_status()
            workers = response.json()
            valkey_client.setex(WORKERS_KEY, DATA_TTL, json.dumps(workers))

            # Fetch miners
            response = requests.get(f"{base_url}/1/miners", headers=headers, timeout=5)
            response.raise_for_status()
            miners = response.json()
            valkey_client.setex(MINERS_KEY, DATA_TTL, json.dumps(miners))

            print(f"Stats updated at {time.ctime()}")
        except requests.RequestException as e:
            print(f"Error fetching stats from XMRig Proxy: {e}")
        except redis.RedisError as e:
            print(f"Error storing stats in Valkey: {e}")
        except Exception as e:
            print(f"Unexpected error in fetch_and_store_stats: {e}")
        
        time.sleep(UPDATE_INTERVAL)

# HTTP handler
class StatsHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        parsed_path = urlparse(self.path)
        if parsed_path.path == "/stats":
            try:
                # Retrieve data from Valkey
                summary = valkey_client.get(SUMMARY_KEY) or "{}"
                workers = valkey_client.get(WORKERS_KEY) or '{"workers": []}'
                miners = valkey_client.get(MINERS_KEY) or '{"miners": []}'
                hashrate_history = valkey_client.zrange(HASHRATE_HISTORY_KEY, 0, -1, withscores=True)

                # Format hashrate history
                history = [{"timestamp": float(score), "hashrate": float(value)} 
                          for value, score in hashrate_history]

                # Send response
                self.send_response(200)
                self.send_header("Content-type", "application/json")
                self.send_header("Access-Control-Allow-Origin", "*")  # Allow CORS for local testing
                self.end_headers()
                response = {
                    "summary": json.loads(summary),
                    "workers": json.loads(workers),
                    "miners": json.loads(miners),
                    "hashrateHistory": history
                }
                self.wfile.write(json.dumps(response).encode())
            except redis.RedisError as e:
                self.send_response(500)
                self.send_header("Content-type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": f"Valkey error: {str(e)}"}).encode())
            except Exception as e:
                self.send_response(500)
                self.send_header("Content-type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": f"Server error: {str(e)}"}).encode())
        else:
            self.send_response(404)
            self.end_headers()

# Start stats collection in a separate thread
def start_stats_collection():
    threading.Thread(target=fetch_and_store_stats, daemon=True).start()

# Start HTTP server
def start_server():
    try:
        with socketserver.TCPServer(("", HTTP_PORT), StatsHandler) as httpd:
            print(f"Serving at http://localhost:{HTTP_PORT}")
            httpd.serve_forever()
    except Exception as e:
        print(f"Failed to start HTTP server on port {HTTP_PORT}: {e}")
        exit(1)

if __name__ == "__main__":
    start_stats_collection()
    start_server()

