#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  Hardware Check & Model Suggestion
#  Kiểm tra phần cứng và gợi ý model Ollama phù hợp
#  Hỗ trợ: macOS & Linux
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ============================================================
#  Detect OS
# ============================================================
detect_os() {
    case "$(uname -s)" in
        Darwin) OS="macos" ;;
        Linux)  OS="linux" ;;
        *)      OS="unknown" ;;
    esac
}

# ============================================================
#  CPU Info
# ============================================================
get_cpu_info() {
    if [[ "$OS" == "macos" ]]; then
        CPU_NAME=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
        CPU_CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo "?")
        CPU_ARCH=$(uname -m)
    else
        CPU_NAME=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "Unknown")
        CPU_CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "?")
        CPU_ARCH=$(uname -m)
    fi
}

# ============================================================
#  RAM Info
# ============================================================
get_ram_info() {
    if [[ "$OS" == "macos" ]]; then
        local ram_bytes
        ram_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
        RAM_TOTAL_GB=$(awk "BEGIN {printf \"%.1f\", $ram_bytes / 1024 / 1024 / 1024}")
        # Available memory on macOS
        local pages_free pages_inactive page_size
        page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
        pages_free=$(vm_stat 2>/dev/null | grep "Pages free" | awk '{print $3}' | tr -d '.')
        pages_inactive=$(vm_stat 2>/dev/null | grep "Pages inactive" | awk '{print $3}' | tr -d '.')
        pages_free=${pages_free:-0}
        pages_inactive=${pages_inactive:-0}
        RAM_AVAIL_GB=$(awk "BEGIN {printf \"%.1f\", ($pages_free + $pages_inactive) * $page_size / 1024 / 1024 / 1024}")
    else
        local ram_total_kb ram_avail_kb
        ram_total_kb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
        ram_avail_kb=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
        RAM_TOTAL_GB=$(awk "BEGIN {printf \"%.1f\", $ram_total_kb / 1024 / 1024}")
        RAM_AVAIL_GB=$(awk "BEGIN {printf \"%.1f\", $ram_avail_kb / 1024 / 1024}")
    fi
}

# ============================================================
#  GPU Info
# ============================================================
get_gpu_info() {
    GPU_NAME="None detected"
    GPU_VRAM_GB="0"
    HAS_GPU=false

    if [[ "$OS" == "macos" ]]; then
        # Apple Silicon có unified memory
        if [[ "$CPU_ARCH" == "arm64" ]]; then
            GPU_NAME="Apple Silicon (unified memory)"
            GPU_VRAM_GB="$RAM_TOTAL_GB"
            HAS_GPU=true
            GPU_TYPE="apple"
        else
            GPU_NAME=$(system_profiler SPDisplaysDataType 2>/dev/null | grep "Chipset Model" | head -1 | cut -d: -f2 | xargs || echo "Unknown")
            local vram
            vram=$(system_profiler SPDisplaysDataType 2>/dev/null | grep "VRAM" | head -1 | grep -oE '[0-9]+' || echo "0")
            GPU_VRAM_GB=$(awk "BEGIN {printf \"%.1f\", ${vram:-0} / 1024}")
            [[ "$GPU_VRAM_GB" != "0" ]] && HAS_GPU=true
            GPU_TYPE="other"
        fi
    else
        # Tìm nvidia-smi (WSL2 đặt tại /usr/lib/wsl/lib/)
        local nvidia_smi=""
        if command -v nvidia-smi &>/dev/null; then
            nvidia_smi="nvidia-smi"
        elif [[ -x /usr/lib/wsl/lib/nvidia-smi ]]; then
            nvidia_smi="/usr/lib/wsl/lib/nvidia-smi"
        fi

        # NVIDIA
        if [[ -n "$nvidia_smi" ]]; then
            GPU_NAME=$($nvidia_smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "Unknown NVIDIA")
            local vram_mb
            vram_mb=$($nvidia_smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")
            GPU_VRAM_GB=$(awk "BEGIN {printf \"%.1f\", ${vram_mb:-0} / 1024}")
            HAS_GPU=true
            GPU_TYPE="nvidia"

            # CUDA version
            CUDA_VERSION=$($nvidia_smi 2>/dev/null | grep -oP "CUDA Version: \K[0-9.]+" || echo "N/A")

            # WSL2 detection
            if grep -qi microsoft /proc/version 2>/dev/null; then
                GPU_NAME="$GPU_NAME (WSL2 passthrough)"
            fi
        # AMD ROCm
        elif command -v rocm-smi &>/dev/null; then
            GPU_NAME=$(rocm-smi --showproductname 2>/dev/null | grep "Card" | head -1 | awk -F: '{print $2}' | xargs || echo "Unknown AMD")
            local vram_mb
            vram_mb=$(rocm-smi --showmeminfo vram 2>/dev/null | grep "Total" | awk '{print $3}' || echo "0")
            GPU_VRAM_GB=$(awk "BEGIN {printf \"%.1f\", ${vram_mb:-0} / 1024 / 1024}")
            HAS_GPU=true
            GPU_TYPE="amd"
        fi
    fi
}

# ============================================================
#  Disk Info
# ============================================================
get_disk_info() {
    if [[ "$OS" == "macos" ]]; then
        DISK_AVAIL=$(df -h / 2>/dev/null | tail -1 | awk '{print $4}')
    else
        DISK_AVAIL=$(df -h / 2>/dev/null | tail -1 | awk '{print $4}')
    fi
}

# ============================================================
#  Ollama Status
# ============================================================
get_ollama_info() {
    OLLAMA_INSTALLED=false
    OLLAMA_RUNNING=false
    OLLAMA_MODELS=""

    if command -v ollama &>/dev/null; then
        OLLAMA_INSTALLED=true
        if curl -sf http://localhost:11434/api/tags &>/dev/null; then
            OLLAMA_RUNNING=true
            OLLAMA_MODELS=$(ollama list 2>/dev/null | tail -n +2 || true)
        fi
    fi
}

# ============================================================
#  Suggest Models
# ============================================================
suggest_models() {
    # Tính RAM khả dụng cho model (trừ ~2GB cho OS + OpenClaw)
    local usable_ram
    if [[ "$HAS_GPU" == true && "$GPU_TYPE" == "nvidia" ]]; then
        # GPU NVIDIA: dùng VRAM
        usable_ram=$(awk "BEGIN {printf \"%.1f\", $GPU_VRAM_GB}")
    elif [[ "$HAS_GPU" == true && "$GPU_TYPE" == "apple" ]]; then
        # Apple Silicon: unified memory, trừ 4GB cho hệ thống
        usable_ram=$(awk "BEGIN {printf \"%.1f\", $RAM_TOTAL_GB - 4}")
    else
        # CPU only: dùng RAM, trừ 3GB cho hệ thống
        usable_ram=$(awk "BEGIN {printf \"%.1f\", $RAM_TOTAL_GB - 3}")
    fi

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  Model Suggestions  ${NC}${DIM}(RAM khả dụng cho model: ~${usable_ram}GB)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    printf "  ${BOLD}%-22s %-8s %-10s %-10s %s${NC}\n" "Model" "Params" "RAM" "Disk" "Status"
    echo "  ──────────────────── ──────── ────────── ────────── ──────────"

    # Model database: name, params, ram_gb, disk_gb
    local models=(
        "qwen2.5:0.5b|0.5B|0.5|0.4"
        "qwen2.5:1.5b|1.5B|1.2|1.0"
        "qwen2.5:3b|3B|2.5|2.0"
        "qwen2.5:7b|7B|5.0|4.7"
        "qwen2.5:14b|14B|10.0|9.0"
        "qwen2.5:32b|32B|20.0|18.0"
        "qwen2.5:72b|72B|44.0|41.0"
        "llama3:8b|8B|5.0|4.7"
        "llama3:70b|70B|40.0|39.0"
        "gemma2:2b|2B|2.0|1.6"
        "gemma2:9b|9B|6.0|5.4"
        "gemma2:27b|27B|18.0|16.0"
        "mistral:7b|7B|5.0|4.1"
        "phi3:3.8b|3.8B|3.0|2.3"
        "phi3:14b|14B|10.0|7.9"
        "deepseek-r1:1.5b|1.5B|1.2|1.1"
        "deepseek-r1:7b|7B|5.0|4.7"
        "deepseek-r1:8b|8B|5.5|4.9"
        "deepseek-r1:14b|14B|10.0|9.0"
        "deepseek-r1:32b|32B|20.0|19.0"
        "deepseek-r1:70b|70B|44.0|41.0"
        "codellama:7b|7B|5.0|3.8"
        "codellama:13b|13B|9.0|7.4"
        "codellama:34b|34B|21.0|19.0"
    )

    local recommended=""
    local best_model=""
    local best_ram=0

    for entry in "${models[@]}"; do
        IFS='|' read -r name params ram disk <<< "$entry"

        local status=""
        local color=""
        local fits
        fits=$(awk "BEGIN {print ($usable_ram >= $ram) ? 1 : 0}")

        if [[ "$fits" == "1" ]]; then
            # Kiểm tra đã cài chưa
            if [[ -n "$OLLAMA_MODELS" ]] && echo "$OLLAMA_MODELS" | grep -q "${name%%:*}"; then
                status="${GREEN}✓ Installed${NC}"
            else
                status="${GREEN}✓ OK${NC}"
            fi
            color="${NC}"

            # Track best model (lớn nhất mà vẫn chạy được)
            local ram_int
            ram_int=$(echo "$ram" | cut -d. -f1)
            if [[ "$ram_int" -gt "$best_ram" ]]; then
                best_ram=$ram_int
                best_model=$name
            fi
        else
            status="${RED}✗ Thiếu RAM${NC}"
            color="${DIM}"
        fi

        printf "  ${color}%-22s %-8s %-10s %-10s${NC} %b\n" "$name" "$params" "${ram}GB" "${disk}GB" "$status"
    done

    echo ""

    if [[ -n "$best_model" ]]; then
        echo -e "  ${GREEN}${BOLD}★ Đề xuất: $best_model${NC}"
        echo -e "  ${DIM}Model lớn nhất phù hợp với phần cứng hiện tại.${NC}"
        echo ""
        echo -e "  Cài đặt nhanh:"
        echo -e "    ${CYAN}ollama pull $best_model${NC}"
        echo -e "    ${CYAN}OLLAMA_MODEL=$best_model ./deploy-ollama.sh${NC}"
    else
        echo -e "  ${RED}Không có model nào phù hợp với RAM hiện tại.${NC}"
        echo -e "  ${DIM}Cần ít nhất 1GB RAM khả dụng.${NC}"
    fi
    echo ""
}

# ============================================================
#  Print Report
# ============================================================
print_report() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    Hardware Check Report                            ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # --- OS ---
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  System${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "  OS:           $(uname -s) $(uname -r)"
    echo "  Hostname:     $(hostname)"
    echo ""

    # --- CPU ---
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  CPU${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "  Model:        $CPU_NAME"
    echo "  Cores:        $CPU_CORES"
    echo "  Architecture: $CPU_ARCH"
    echo ""

    # --- RAM ---
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  RAM${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "  Total:        ${RAM_TOTAL_GB}GB"
    echo "  Available:    ${RAM_AVAIL_GB}GB"

    # RAM bar
    if [[ "$RAM_TOTAL_GB" != "?" && "$RAM_AVAIL_GB" != "?" ]]; then
        local used pct bar_len filled empty
        used=$(awk "BEGIN {printf \"%.1f\", $RAM_TOTAL_GB - $RAM_AVAIL_GB}")
        pct=$(awk "BEGIN {printf \"%d\", $used * 100 / $RAM_TOTAL_GB}")
        bar_len=40
        filled=$(awk "BEGIN {printf \"%d\", $pct * $bar_len / 100}")
        empty=$((bar_len - filled))

        local bar_color="${GREEN}"
        [[ "$pct" -gt 60 ]] && bar_color="${YELLOW}"
        [[ "$pct" -gt 85 ]] && bar_color="${RED}"

        printf "  Used:         ${bar_color}"
        printf '█%.0s' $(seq 1 "$filled" 2>/dev/null || true)
        printf "${DIM}"
        printf '░%.0s' $(seq 1 "$empty" 2>/dev/null || true)
        printf "${NC} %s%% (${used}GB)\n" "$pct"
    fi
    echo ""

    # --- GPU ---
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  GPU${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "  GPU:          $GPU_NAME"
    if [[ "$HAS_GPU" == true ]]; then
        [[ "$GPU_TYPE" != "apple" ]] && echo "  VRAM:         ${GPU_VRAM_GB}GB"
        [[ -n "${CUDA_VERSION:-}" ]] && echo "  CUDA:         $CUDA_VERSION"
    else
        echo -e "  ${DIM}Không phát hiện GPU. Model sẽ chạy trên CPU (chậm hơn).${NC}"
    fi
    echo ""

    # --- Disk ---
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  Disk${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "  Available:    $DISK_AVAIL"
    echo ""

    # --- Ollama ---
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  Ollama${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    if [[ "$OLLAMA_INSTALLED" == true ]]; then
        echo -e "  Installed:    ${GREEN}Yes${NC}"
        if [[ "$OLLAMA_RUNNING" == true ]]; then
            echo -e "  Server:       ${GREEN}Running${NC} (http://localhost:11434)"
            if [[ -n "$OLLAMA_MODELS" ]]; then
                echo "  Models:"
                echo "$OLLAMA_MODELS" | while read -r line; do
                    echo "                $line"
                done
            else
                echo -e "  Models:       ${DIM}None${NC}"
            fi
        else
            echo -e "  Server:       ${RED}Not running${NC}"
            echo -e "  ${DIM}Start with: ollama serve${NC}"
        fi
    else
        echo -e "  Installed:    ${RED}No${NC}"
        echo -e "  ${DIM}Install with: ./deploy-ollama.sh${NC}"
    fi
    echo ""

    # --- Model Suggestions ---
    suggest_models
}

# ============================================================
#  Main
# ============================================================
main() {
    detect_os
    get_cpu_info
    get_ram_info
    get_gpu_info
    get_disk_info
    get_ollama_info
    print_report
}

main "$@"
