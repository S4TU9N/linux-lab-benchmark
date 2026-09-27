#!/usr/bin/env bash

# linux lab benchmark
# linux implementation

set +e

OS_NAME="Linux"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/../results"
OUTPUT_PATH="$RESULTS_DIR/linux.csv"

mkdir -p "$RESULTS_DIR"

echo
echo "Linux Lab Benchmark - Linux"
echo "==========================="
echo "Timestamp: $TIMESTAMP"
echo

RESULTS=()

add_result() {
    local category="$1"
    local stat="$2"
    local value="$3"
    local unit="$4"

    RESULTS+=("$OS_NAME"$'\t'"$category"$'\t'"$stat"$'\t'"$value"$'\t'"$unit")
}

# system information

if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_NAME="${PRETTY_NAME:-$NAME}"
else
    DISTRO_NAME="Unknown"
fi

KERNEL_VERSION="$(uname -r)"

CPU_MODEL="$(awk -F: '/model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo)"

if command -v lscpu >/dev/null 2>&1; then
    CPU_CORES="$(lscpu -b -p=CORE | grep -v '^#' | sort -u | wc -l)"
    CPU_THREADS="$(lscpu -b -p=CPU | grep -v '^#' | wc -l)"
else
    CPU_CORES="$(grep -c '^processor' /proc/cpuinfo)"
    CPU_THREADS="$CPU_CORES"
fi

if [ -r /proc/meminfo ]; then
    RAM_TOTAL_KB="$(awk '/MemTotal:/ {print $2}' /proc/meminfo)"
    RAM_TOTAL_GB="$(awk '/MemTotal:/ {printf "%.2f", $2 / 1024 / 1024}' /proc/meminfo)"
else
    RAM_TOTAL_GB="unknown"
fi

GPU_MODEL="unknown"

if command -v lspci >/dev/null 2>&1; then
    GPU_MODEL="$(lspci | grep -Ei 'VGA compatible controller|3D controller|Display controller' | head -n 1 | sed 's/^[^:]*: //')"
fi

add_result "system" "os" "$DISTRO_NAME" "text"
add_result "system" "kernel" "$KERNEL_VERSION" "text"
add_result "system" "cpu_model" "$CPU_MODEL" "text"
add_result "system" "cpu_cores" "$CPU_CORES" "count"
add_result "system" "cpu_threads" "$CPU_THREADS" "count"
add_result "system" "ram_total" "$RAM_TOTAL_GB" "GB"
add_result "system" "gpu_model" "$GPU_MODEL" "text"

# storage information

if command -v lsblk >/dev/null 2>&1; then
    while IFS='|' read -r disk_name disk_size disk_model; do
        [ -z "$disk_name" ] && continue

        add_result "storage" "disk_device" "$disk_name" "text"
        add_result "storage" "disk_size" "$disk_size" "text"
        add_result "storage" "disk_model" "$disk_model" "text"
    done < <(
        lsblk -dn -o NAME,SIZE,MODEL,TYPE -P |
        awk '
        {
            name=""; size=""; model=""; type=""

            for (i = 1; i <= NF; i++) {
                if ($i ~ /^NAME=/)  { name=$i;  sub(/^NAME="/, "", name);  sub(/"$/, "", name) }
                if ($i ~ /^SIZE=/)  { size=$i;  sub(/^SIZE="/, "", size);  sub(/"$/, "", size) }
                if ($i ~ /^MODEL=/) { model=$i; sub(/^MODEL="/, "", model); sub(/"$/, "", model) }
                if ($i ~ /^TYPE=/)  { type=$i;  sub(/^TYPE="/, "", type);  sub(/"$/, "", type) }
            }

            if (type == "disk")
                print name "|" size "|" model
        }'
    )
fi

# idle resource usage

echo "Letting the system settle for 30 seconds..."
sleep 30

echo "Collecting idle resource usage..."

CPU_TOTAL_START="$(awk '/^cpu / {
    idle=$5
    total=0
    for (i=2; i<=NF; i++) total += $i
    print total, idle
}' /proc/stat)"

sleep 1

CPU_TOTAL_END="$(awk '/^cpu / {
    idle=$5
    total=0
    for (i=2; i<=NF; i++) total += $i
    print total, idle
}' /proc/stat)"

read -r TOTAL_START IDLE_START <<< "$CPU_TOTAL_START"
read -r TOTAL_END IDLE_END <<< "$CPU_TOTAL_END"

TOTAL_DIFF=$((TOTAL_END - TOTAL_START))
IDLE_DIFF=$((IDLE_END - IDLE_START))

if [ "$TOTAL_DIFF" -gt 0 ]; then
    IDLE_CPU="$(awk -v idle="$IDLE_DIFF" -v total="$TOTAL_DIFF" 'BEGIN {
        printf "%.2f", (1 - idle / total) * 100
    }')"
else
    IDLE_CPU="unknown"
fi

RAM_USED_GB="$(awk '
/^MemTotal:/ { total=$2 }
/^MemAvailable:/ { available=$2 }
END {
    printf "%.2f", (total - available) / 1024 / 1024
}' /proc/meminfo)"

RAM_USED_PERCENT="$(awk -v used="$RAM_USED_GB" -v total="$RAM_TOTAL_GB" 'BEGIN {
    if (total > 0)
        printf "%.2f", used / total * 100
    else
        print "unknown"
}')"

add_result "idle" "idle_cpu" "$IDLE_CPU" "percent"
add_result "idle" "idle_ram" "$RAM_USED_GB" "GB"
add_result "idle" "idle_ram_percent" "$RAM_USED_PERCENT" "percent"

# process count

if command -v ps >/dev/null 2>&1; then
    PROCESS_COUNT="$(ps -e --no-headers | wc -l)"
    add_result "idle" "process_count" "$PROCESS_COUNT" "count"
fi

# export

{
    echo "os,category,stat,value,unit"

    for result in "${RESULTS[@]}"; do
        IFS=$'\t' read -r os category stat value unit <<< "$result"

        os="${os//\"/\"\"}"
        category="${category//\"/\"\"}"
        stat="${stat//\"/\"\"}"
        value="${value//\"/\"\"}"
        unit="${unit//\"/\"\"}"

        echo "\"$os\",\"$category\",\"$stat\",\"$value\",\"$unit\""
    done
} > "$OUTPUT_PATH"

echo
echo "Benchmark complete."
echo "Results: $OUTPUT_PATH"
echo
echo "Collected results:"
column -t -s ',' "$OUTPUT_PATH" 2>/dev/null || cat "$OUTPUT_PATH"
