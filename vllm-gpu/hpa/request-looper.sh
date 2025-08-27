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
request_count=0
start_time=$(date +%s)


# Cleanup function to be called on exit. This function iterates through the
# stored PIDs and terminates each corresponding process.
cleanup() {
    echo -e "\n\nCaught signal. Shutting down gracefully..."

    # --- Summary ---
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    echo "----------------------------------------"
    echo "Test Summary"
    echo "----------------------------------------"
    echo "Total Requests Sent: ${request_count}"
    echo "Total Duration: ${duration}s"
    echo "----------------------------------------"


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
  ((request_count++))
  echo -ne "Sending request #${request_count}..."

  # This block runs in a background subshell (&) for each request.
  (
    # Execute curl, capturing the response body and appending the HTTP status code
    # on a new line. The -s flag silences the progress meter.
    output=$(curl -s -w "\n%{http_code}" -X POST "$URL" \
      -H "Content-Type: application/json" \
      -d "$JSON_PAYLOAD")

    # Extract the HTTP status code (which is the last line of the output).
    http_code="${output##*

'}"

    # Check if the status code is not a success code (i.e., not 2xx).
    if [[ "$http_code" -lt 200 || "$http_code" -gt 299 ]]; then
      # If it's an error, extract the response body (everything except the last line).
      response_body="${output%

'*}"
      # Print a formatted error message to stderr.
      echo -e "\n---" >&2
      echo "ERROR: Request #${request_count} failed at $(date) with Status: ${http_code}" >&2
      echo "Response Body:" >&2
      echo "${response_body}" >&2
      echo -e "---\n" >&2
    fi
  ) &

  # Store the PID of the last background process in the pids array.
  pids+=($!)

  # Wait for 1 second before the next request.
  sleep 1
done
