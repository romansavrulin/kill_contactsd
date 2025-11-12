#!/bin/bash
# Set the CPU usage threshold (in percent)
CPU_THRESHOLD=50.0

# Time interval between checks (in seconds, e.g., 300 seconds = 5 minutes)
INTERVAL=60

# Flag to indicate if the script should run only once
run_once=false
run_always=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -o|--run_once)
      run_once=true
      shift # past arg
      ;;
    -a|--run_always)
      run_always=true
      shift # past arg
      ;;
    -i|--interval)
      INTERVAL="$2"
      shift # past arg
      shift # past val
      ;;
    -t|--cpu_threshold)
      CPU_THRESHOLD="$2"
      shift # past arg
      shift # past val
      ;;
    -*|--*|*)
      echo "Unknown option $1"
      exit 1
      ;;
  esac
done

CPU_THRESHOLD=`echo "$CPU_THRESHOLD" | sed 's/,/./'`

# Function to perform the check and kill logic
check_and_kill_contactsd() {
    # Get the power status from pmset
    BATTERY_STATUS=$(pmset -g batt | head -n 1 | awk -F"'" '{print $2}')

    if [[ "$BATTERY_STATUS" = "Battery Power" || "$run_always" = "true" ]]; then
        # Identify contactsd process(es)
        PIDS=$(pgrep -f [c]ontactsd)
        if [ -n "$PIDS" ]; then
            for PID in $PIDS; do
                # Retrieve the CPU usage for this PID; the '=' after %cpu suppresses the header on macOS.
                CPU_USAGE=$(ps -p "$PID" -o %cpu= | tr -d ' '| sed 's/,/./')

                # Validate that CPU_USAGE is a non-empty numeric value.
                if ! [[ $CPU_USAGE =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                    echo "$(date): Failed to retrieve CPU usage for PID $PID."
                    continue
                fi

                # Compare the CPU usage with the threshold using bc for floating-point support.
                if [ "$(echo "$CPU_USAGE > $CPU_THRESHOLD" | bc -l)" -eq 1 ]; then
                    echo "$(date): Process contactsd (PID: $PID) is using ${CPU_USAGE}% CPU. Killing it..."
                    kill -9 "$PID"
                else
                    echo "$(date): Process contactsd (PID: $PID) is using ${CPU_USAGE}% CPU; within limits."
                fi
            done
        else
            echo "$(date): contactsd is not running."
        fi
    else
        echo "$(date): Not on battery power (current source: $BATTERY_STATUS). No action taken."
    fi
}


if [ "$run_once" = true ]; then
    echo "Running once."
    check_and_kill_contactsd
else
    echo -n "Starting contactsd monitor. Checking every ${INTERVAL} seconds with CPU_THRESHOLD = ${CPU_THRESHOLD}"
    if [ "$run_always" = false ]; then
        echo " while on battery."
    else
        echo " regardless of battery status."
    fi
    while true; do
        check_and_kill_contactsd
        # Wait for the specified interval before the next check.
        sleep "$INTERVAL"
    done
fi
