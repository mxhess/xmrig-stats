import http.server
import socketserver
import json
import redis
import requests
import threading
import time
import signal
from urllib.parse import urlparse, parse_qs
import socket
from collections import deque
import sys

# Configuration
PROXY_HOST = "127.0.0.1"
PROXY_PORT = 8080
ACCESS_TOKEN = ""  # Set if required
VALKEY_HOST = "localhost"
VALKEY_PORT = 6379
UPDATE_INTERVAL = 5  # Seconds
DATA_TTL = 12 * 60 * 60  # 3 hours in seconds
HTTP_PORT = 8282  # Avoid Docker Proxy conflict
DEFAULT_HISTORY_SECONDS = 1800  # 30 minutes for hashrate history
MAX_RETRIES = 3
RETRY_DELAY = 5
HISTORY_BUFFER_SIZE = 360  # 30 minutes / 5 seconds = 360 points

# Valkey keys
SUMMARY_KEY = "xmrig:summary"
WORKERS_KEY = "xmrig:workers"
MINERS_KEY = "xmrig:miners"
HASHRATE_HISTORY_KEY = "xmrig:hashrate_history"

# Global variables
httpd = None
stats_thread = None
history_buffer = deque(maxlen=HISTORY_BUFFER_SIZE)
last_served_time = 0  # Track last served timestamp for updates
buffer_lock = threading.Lock()  # Add thread safety

# Initialize Valkey client
try:
    valkey_client = redis.Redis(host=VALKEY_HOST, port=VALKEY_PORT, decode_responses=True)
    valkey_client.ping()
    print("Connected to Valkey successfully")
except redis.ConnectionError as e:
    print(f"Failed to connect to Valkey at {VALKEY_HOST}:{VALKEY_PORT}: {e}")
    exit(1)

# Resource check (placeholder, expand as needed)
def check_resources():
    return True  # Replace with actual memory/CPU check if needed

# Fetch and store stats with retry and watchdog
def fetch_and_store_stats():
    global last_served_time
    last_update = time.time()
    consecutive_failures = 0
    
    while True:
        if not check_resources():
            time.sleep(UPDATE_INTERVAL)
            continue
        
        success = False
        for attempt in range(MAX_RETRIES):
            try:
                timestamp = int(time.time())
                headers = {"Authorization": f"Bearer {ACCESS_TOKEN}"} if ACCESS_TOKEN else {}
                base_url = f"http://{PROXY_HOST}:{PROXY_PORT}"

                # Fetch and store summary
                response = requests.get(f"{base_url}/1/summary", headers=headers, timeout=10)
                response.raise_for_status()
                summary = response.json()
                valkey_client.setex(SUMMARY_KEY, DATA_TTL, json.dumps(summary))
                
                # Extract hashrate - handle different possible structures
                hashrate = 0
                if "hashrate" in summary:
                    hr_data = summary["hashrate"]
                    if isinstance(hr_data, dict):
                        if "total" in hr_data:
                            total = hr_data["total"]
                            if isinstance(total, list) and len(total) > 0:
                                hashrate = total[0] or 0
                            elif isinstance(total, (int, float)):
                                hashrate = total
                        # Also try other possible keys
                        elif "highest" in hr_data:
                            hashrate = hr_data["highest"] or 0
                        elif "current" in hr_data:
                            hashrate = hr_data["current"] or 0
                    elif isinstance(hr_data, (int, float)):
                        hashrate = hr_data
                
                # If still 0, try other possible locations in the summary
                if hashrate == 0:
                    # Try direct access to workers or connection data
                    if "connection" in summary and isinstance(summary["connection"], dict):
                        if "pool" in summary["connection"]:
                            pool_data = summary["connection"]["pool"]
                            if isinstance(pool_data, dict) and "hashrate" in pool_data:
                                hashrate = pool_data["hashrate"] or 0
                    
                    # Try results section
                    if "results" in summary and isinstance(summary["results"], dict):
                        if "hashrate" in summary["results"]:
                            hashrate = summary["results"]["hashrate"] or 0
                
                # Debug: Show the entire summary structure when hashrate is 0
                if hashrate == 0:
                    print(f"DEBUG: hashrate is 0, summary structure: {json.dumps(summary, indent=2)}")
                
                print(f"Extracted hashrate: {hashrate} at timestamp {timestamp}")
                
                # Store in buffer with thread safety
                with buffer_lock:
                    history_buffer.append((timestamp, hashrate))
                    
                    # Write each point immediately to Valkey - FIXED: correct Python redis syntax
                    try:
                        # Python redis library format: zadd(key, {member: score})
                        # We want timestamp as score for range queries, hashrate as member
                        member_key = f"{hashrate}:{timestamp}"  # Composite member for uniqueness
                        valkey_client.zadd(HASHRATE_HISTORY_KEY, {member_key: timestamp})
                        
                        # Set expiration and clean old data every 10 points to reduce overhead
                        if len(history_buffer) % 10 == 0:
                            valkey_client.expire(HASHRATE_HISTORY_KEY, DATA_TTL)
                            cutoff_time = timestamp - DATA_TTL
                            removed = valkey_client.zremrangebyscore(HASHRATE_HISTORY_KEY, 0, cutoff_time)
                            if removed > 0:
                                print(f"Cleaned {removed} old points (older than {cutoff_time})")
                        
                        print(f"Stored: {member_key} with score {timestamp}")
                        
                    except redis.RedisError as re:
                        print(f"Error storing single point in Valkey: {re}")
                        continue

                # Fetch and store workers
                response = requests.get(f"{base_url}/1/workers", headers=headers, timeout=10)
                response.raise_for_status()
                workers = response.json()
                valkey_client.setex(WORKERS_KEY, DATA_TTL, json.dumps(workers))

                # Fetch and store miners
                response = requests.get(f"{base_url}/1/miners", headers=headers, timeout=10)
                response.raise_for_status()
                miners = response.json()
                valkey_client.setex(MINERS_KEY, DATA_TTL, json.dumps(miners))

                print(f"Stats updated at {time.ctime()}, hashrate: {hashrate}")
                print(f"Buffer size: {len(history_buffer)}")
                sys.stdout.flush()
                
                last_update = time.time()
                consecutive_failures = 0
                success = True
                break
                
            except requests.RequestException as e:
                consecutive_failures += 1
                if attempt == MAX_RETRIES - 1:
                    print(f"Failed to fetch stats after {MAX_RETRIES} retries at {time.ctime()}: {e}")
                    print(f"Consecutive failures: {consecutive_failures}")
                    sys.stdout.flush()
                time.sleep(RETRY_DELAY)
            except redis.RedisError as e:
                consecutive_failures += 1
                print(f"Error storing stats in Valkey at {time.ctime()}: {e}")
                sys.stdout.flush()
                break
            except Exception as e:
                consecutive_failures += 1
                print(f"Unexpected error in fetch_and_store_stats at {time.ctime()}: {e}")
                sys.stdout.flush()
                break
        
        # Emergency restart if too many consecutive failures
        if consecutive_failures > 10:
            print(f"Too many consecutive failures ({consecutive_failures}), restarting stats thread")
            sys.stdout.flush()
            consecutive_failures = 0
        
        # Watchdog: Restart if stalled
        if time.time() - last_update > UPDATE_INTERVAL * 3:
            print(f"Watchdog detected stall at {time.ctime()}, restarting loop")
            sys.stdout.flush()
            last_update = time.time()
        
        time.sleep(UPDATE_INTERVAL)

# HTTP handler
class StatsHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Suppress default HTTP logging to reduce noise
        pass
    
    def do_GET(self):
        global last_served_time
        parsed_path = urlparse(self.path)
        if parsed_path.path == "/stats":
            try:
                query = parse_qs(parsed_path.query)
                update_only = query.get('update', ['false'])[0].lower() == 'true'
                time_range = int(query.get('time_range', [DEFAULT_HISTORY_SECONDS if not update_only else 5])[0])
                time_range = max(60, min(time_range, DATA_TTL))
                current_time = int(time.time())
                start_time = int(query.get('start', [current_time - time_range if not update_only else max(last_served_time, current_time - time_range)])[0])

                print(f"HTTP Request: update_only={update_only}, time_range={time_range}, start_time={start_time}, current_time={current_time}")

                summary = valkey_client.get(SUMMARY_KEY) or "{}"
                workers = valkey_client.get(WORKERS_KEY) or '{"workers": []}'
                miners = valkey_client.get(MINERS_KEY) or '{"miners": []}'
                
                # Check if we have any data in Valkey at all
                total_points = valkey_client.zcard(HASHRATE_HISTORY_KEY)
                print(f"Total points in Valkey: {total_points}")
                
                end_time = min(current_time, start_time + time_range)
                
                # FIXED: Query by score (timestamp) range and parse correctly
                hashrate_data = valkey_client.zrangebyscore(
                    HASHRATE_HISTORY_KEY, start_time, end_time, withscores=True
                )
                
                print(f"Raw Valkey data: {hashrate_data[:3]}...")  # Debug: show first 3 items
                
                # FIXED: Parse the composite keys correctly
                history = []
                seen_timestamps = set()
                
                for member, score in hashrate_data:
                    try:
                        # Parse composite key "hashrate:timestamp"
                        if ':' in str(member):
                            parts = str(member).split(':', 1)
                            if len(parts) == 2:
                                hr_str, ts_str = parts
                                timestamp = int(float(score))  # Use score as timestamp
                                hashrate = float(hr_str)
                                
                                if timestamp not in seen_timestamps:
                                    history.append({"timestamp": timestamp, "hashrate": hashrate})
                                    seen_timestamps.add(timestamp)
                        else:
                            print(f"Skipping malformed member: {member}")
                    except (ValueError, AttributeError) as e:
                        print(f"Error parsing history data: {member}, {score}: {e}")
                        continue
                
                print(f"Parsed {len(history)} valid points")  # Debug info
                
                # Sort by timestamp - don't fill gaps, just return the real data
                history.sort(key=lambda x: x["timestamp"])
                
                print(f"Returning {len(history)} real data points (no gap filling)")
                
                # Optional: If you want some gap filling, only fill small gaps (< 30 seconds)
                if len(history) > 1:
                    filled_history = []
                    for i, point in enumerate(history):
                        filled_history.append(point)
                        
                        # Fill small gaps only
                        if i < len(history) - 1:
                            next_point = history[i + 1]
                            gap = next_point["timestamp"] - point["timestamp"]
                            if 5 < gap <= 30:  # Fill gaps between 5-30 seconds
                                current_ts = point["timestamp"] + 5
                                while current_ts < next_point["timestamp"]:
                                    filled_history.append({"timestamp": current_ts, "hashrate": 0.0})
                                    current_ts += 5
                    history = filled_history
                
                if not update_only and history:
                    last_served_time = history[-1]["timestamp"]
                
                print(f"Serving {len(history)} hashrate points for {time_range}s from {start_time} to {end_time}")

                self.send_response(200)
                self.send_header("Content-type", "application/json")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Cache-Control", "no-cache")
                self.end_headers()
                
                response = {
                    "summary": json.loads(summary),
                    "workers": json.loads(workers),
                    "miners": json.loads(miners),
                    "hashrateHistory": history
                }
                self.wfile.write(json.dumps(response).encode())
                
            except redis.RedisError as e:
                print(f"Valkey error in HTTP handler: {e}")
                self.send_response(500)
                self.send_header("Content-type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": f"Valkey error: {str(e)}"}).encode())
            except Exception as e:
                print(f"HTTP handler error: {e}")
                self.send_response(500)
                self.send_header("Content-type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": f"Server error: {str(e)}"}).encode())
        elif parsed_path.path == "/debug":
            # Debug endpoint to check Valkey data
            try:
                total_points = valkey_client.zcard(HASHRATE_HISTORY_KEY)
                latest_points = valkey_client.zrevrange(HASHRATE_HISTORY_KEY, 0, 4, withscores=True)
                oldest_points = valkey_client.zrange(HASHRATE_HISTORY_KEY, 0, 4, withscores=True)
                
                debug_info = {
                    "total_points": total_points,
                    "latest_5": latest_points,
                    "oldest_5": oldest_points,
                    "key_exists": valkey_client.exists(HASHRATE_HISTORY_KEY),
                    "key_type": valkey_client.type(HASHRATE_HISTORY_KEY),
                    "current_time": int(time.time())
                }
                
                self.send_response(200)
                self.send_header("Content-type", "application/json")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(json.dumps(debug_info, indent=2).encode())
                
            except Exception as e:
                self.send_response(500)
                self.send_header("Content-type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode())
        
        elif parsed_path.path == "/debug/proxy":
            # Debug endpoint to check what XMRig proxy is returning
            try:
                headers = {"Authorization": f"Bearer {ACCESS_TOKEN}"} if ACCESS_TOKEN else {}
                base_url = f"http://{PROXY_HOST}:{PROXY_PORT}"
                
                # Fetch raw summary
                response = requests.get(f"{base_url}/1/summary", headers=headers, timeout=10)
                response.raise_for_status()
                raw_summary = response.json()
                
                self.send_response(200)
                self.send_header("Content-type", "application/json")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(json.dumps(raw_summary, indent=2).encode())
                
            except Exception as e:
                self.send_response(500)
                self.send_header("Content-type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode())
        else:
            self.send_response(404)
            self.end_headers()

# Shutdown handler
def shutdown_handler(signum, frame):
    global httpd, stats_thread
    print(f"Received shutdown signal {signum}, shutting down...")
    if httpd:
        httpd.shutdown()
        httpd.server_close()
        if hasattr(httpd, 'socket'):
            httpd.socket.close()
    if stats_thread:
        stats_thread.join(timeout=2)
    print("Shutdown complete")
    exit(0)

# Custom TCPServer to allow address reuse
class ReuseTCPServer(socketserver.TCPServer):
    allow_reuse_address = True

# Start stats collection
def start_stats_collection():
    global stats_thread
    stats_thread = threading.Thread(target=fetch_and_store_stats, daemon=True)
    stats_thread.start()

# Start HTTP server
def start_server():
    global httpd
    try:
        server = ReuseTCPServer(("", HTTP_PORT), StatsHandler)
        httpd = server
        print(f"Serving at http://localhost:{HTTP_PORT}")
        server.serve_forever()
    except Exception as e:
        print(f"Failed to start HTTP server on port {HTTP_PORT}: {e}")
        if httpd:
            httpd.server_close()
        exit(1)

if __name__ == "__main__":
    signal.signal(signal.SIGINT, shutdown_handler)
    signal.signal(signal.SIGTERM, shutdown_handler)
    
    start_stats_collection()
    start_server()

