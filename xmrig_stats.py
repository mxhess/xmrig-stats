import http.server
import socketserver
import json
import redis
import requests
import threading
import time
from urllib.parse import urlparse, parse_qs

# Configuration
PROXY_HOST = "127.0.0.1"
PROXY_PORT = 8080
ACCESS_TOKEN = ""  # Set if required
VALKEY_HOST = "localhost"
VALKEY_PORT = 6379
UPDATE_INTERVAL = 5  # Seconds
DATA_TTL = 3 * 60 * 60  # 3 hours in seconds
HTTP_PORT = 8282  # Avoid Docker Proxy conflict
DEFAULT_HISTORY_SECONDS = 1800  # 30 minutes for hashrate history

# Valkey keys
SUMMARY_KEY = "xmrig:summary"
WORKERS_KEY = "xmrig:workers"
MINERS_KEY = "xmrig:miners"
HASHRATE_HISTORY_KEY = "xmrig:hashrate_history"

# Initialize Valkey client
try:
    valkey_client = redis.Redis(host=VALKEY_HOST, port=VALKEY_PORT, decode_responses=True)
    valkey_client.ping()
    print("Connected to Valkey successfully")
except redis.ConnectionError as e:
    print(f"Failed to connect to Valkey at {VALKEY_HOST}:{VALKEY_PORT}: {e}")
    exit(1)

# Fetch and store stats
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
                # Parse query parameters
                query = parse_qs(parsed_path.query)
                time_range = int(query.get('time_range', [DEFAULT_HISTORY_SECONDS])[0])
                time_range = max(60, min(time_range, DATA_TTL))  # Clamp between 1 minute and 3 hours
                start_time = int(query.get('start', [int(time.time()) - time_range])[0])

                # Retrieve data from Valkey
                summary = valkey_client.get(SUMMARY_KEY) or "{}"
                workers = valkey_client.get(WORKERS_KEY) or '{"workers": []}'
                miners = valkey_client.get(MINERS_KEY) or '{"miners": []}'
                
                # Fetch hashrate history
                current_time = int(time.time())
                end_time = min(current_time, start_time + time_range)
                hashrate_history = valkey_client.zrangebyscore(
                    HASHRATE_HISTORY_KEY, start_time, end_time, withscores=True
                )
                
                # Format hashrate history with gap filling
                history = []
                last_timestamp = start_time
                for value, score in hashrate_history:
                    timestamp = float(score)
                    # Fill gaps with 0 hashrate for missing 5-second intervals
                    while last_timestamp < timestamp:
                        history.append({"timestamp": last_timestamp, "hashrate": 0.0})
                        last_timestamp += 5
                    history.append({"timestamp": timestamp, "hashrate": float(value)})
                    last_timestamp = timestamp + 5
                # Fill up to end_time
                while last_timestamp <= end_time:
                    history.append({"timestamp": last_timestamp, "hashrate": 0.0})
                    last_timestamp += 5
                
                print(f"Serving {len(history)} hashrate points for {time_range}s from {start_time} to {end_time}")

                # Send response
                self.send_response(200)
                self.send_header("Content-type", "application/json")
                self.send_header("Access-Control-Allow-Origin", "*")
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

# Start stats collection
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

