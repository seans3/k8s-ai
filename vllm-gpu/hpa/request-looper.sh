#!/bin/bash

# This script sends a POST request to a local LLM endpoint every second
# without waiting for a response. It runs until manually stopped by pressing Ctrl+C.
#
# Usage: ./request-looper.sh [PORT] [MODEL_NAME] ["MESSAGE CONTENT"]
#
# Examples:
#   ./request-looper.sh
#   ./request-looper.sh 8082
#   ./request-looper.sh 8082 "google/gemma-2b" "What is the capital of France?"

# --- Configuration (with defaults) ---
# Use command-line arguments if provided, otherwise use defaults.
PORT=${1:-"8081"}
MODEL=${2:-"google/gemma-3-1b-it"}
CONTENT=${3:-"Explain Quantum Computing in simple terms."}

# The URL of the LLM API endpoint.
URL="http://localhost:${PORT}/v1/chat/completions"

# The JSON payload for the request.
JSON_PAYLOAD=$(printf '{
  "model": "%s",
  "messages": [{"role": "user", "content": "%s"}]
}' "$MODEL" "$CONTENT")

# --- Graceful Shutdown Logic ---
# Array to store PIDs of background curl processes.
pids=()

# Cleanup function to be called on exit. This function iterates through the
# stored PIDs and terminates each corresponding process.
cleanup() {
    echo -e "\n\nCaught signal. Shutting down gracefully..."
    echo "Terminating ${#pids[@]} background curl processes."
    # Kill all background processes.
    for pid in "${pids[@]}"; do
        # Use kill -0 to check if the process exists before trying to terminate it.
        if kill -0 "$pid" 2>/dev/null;
        then
            kill -s TERM "$pid"
        fi
    done
    echo "Cleanup complete. Exiting."
    exit 0
}

# Set up the trap to call the cleanup function on SIGINT (Ctrl+C) or SIGTERM.
trap cleanup SIGINT SIGTERM

# --- Script Logic ---
echo "Starting request loop..."
echo "  PORT: $PORT"
echo "  MODEL: $MODEL"
echo "  CONTENT: $CONTENT"
echo "Press Ctrl+C to stop."

# Infinite loop to send requests.
while true
do
  echo "----------------------------------------"
  echo "Sending request at $(date)"

  # Send the POST request using curl and run it in the background (&).
  # The output and errors are redirected to /dev/null to keep the console clean.
  curl -X POST "$URL" \
       -H "Content-Type: application/json" \
       -d "$JSON_PAYLOAD" \
       --silent \
       -o /dev/null \
       -w "HTTP Status: %{http_code}\n" &

  # Store the PID of the last background process in the pids array.
  pids+=($!)

  # Wait for 1 second before the next request.
  sleep 1
done
