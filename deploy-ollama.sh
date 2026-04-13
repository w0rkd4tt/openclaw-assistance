#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  Ollama — Deploy & Model Setup
#  Cài đặt Ollama, khởi động server, chọn và pull model
#  Hỗ trợ: macOS (arm64/x86) & Linux (x86_64)
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[✗]${NC} $*"; exit 1; }
info()  { echo -e "${CYAN}[→]${NC} $*"; }

OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5:32b}"

# ============================================================
#  1. Kiểm tra OS
# ============================================================
detect_os() {
    case "$(uname -s)" in
        Darwin) OS="macos" ;;
        Linux)  OS="linux" ;;
        *)      err "OS không được hỗ trợ: $(uname -s)" ;;
    esac
    log "Hệ điều hành: $OS ($(uname -m))"
}

# ============================================================
#  2. Cài đặt Ollama
# ============================================================
install_ollama() {
    if command -v ollama &>/dev/null; then
        log "Ollama đã có sẵn: $(ollama -v 2>/dev/null || echo 'installed')"
        return
    fi

    info "Cài đặt Ollama..."
    if [[ "$OS" == "macos" ]]; then
        brew install ollama
    else
        # Cài curl nếu chưa có
        if ! command -v curl &>/dev/null; then
            sudo apt-get update -qq && sudo apt-get install -y curl
        fi
        curl -fsSL https://ollama.com/install.sh | sh
    fi
    log "Ollama đã cài xong."
}

# ============================================================
#  3. Khởi động Ollama server
# ============================================================
start_ollama() {
    if curl -sf http://localhost:11434/api/tags &>/dev/null; then
        log "Ollama server đã chạy sẵn."
        return
    fi

    info "Khởi động Ollama server..."
    if [[ "$OS" == "macos" ]]; then
        open -a Ollama 2>/dev/null || ollama serve &
    else
        ollama serve &
    fi

    for i in {1..30}; do
        if curl -sf http://localhost:11434/api/tags &>/dev/null; then
            break
        fi
        sleep 1
        if [[ $i -eq 30 ]]; then
            err "Ollama server không khởi động được sau 30s."
        fi
    done
    log "Ollama server đang chạy tại http://localhost:11434"
}

# ============================================================
#  4. Chọn model
# ============================================================
select_model() {
    EXISTING_MODELS=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' || true)

    if [[ -n "$EXISTING_MODELS" ]]; then
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}  Model Ollama đã có trên máy:${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        local idx=1
        local model_list=()
        while IFS= read -r m; do
            model_list+=("$m")
            echo "    $idx) $m"
            idx=$((idx + 1))
        done <<< "$EXISTING_MODELS"
        echo "    $idx) Nhập model khác (sẽ tự pull)"
        echo ""
        echo -e "  Model mặc định: ${YELLOW}$OLLAMA_MODEL${NC}"
        echo ""
        read -rp "Chọn model [1-$idx, Enter = mặc định]: " model_choice

        if [[ -n "$model_choice" && "$model_choice" =~ ^[0-9]+$ ]]; then
            if [[ "$model_choice" -ge 1 && "$model_choice" -lt "$idx" ]]; then
                OLLAMA_MODEL="${model_list[$((model_choice - 1))]}"
                log "Đã chọn model: $OLLAMA_MODEL"
            elif [[ "$model_choice" -eq "$idx" ]]; then
                print_model_suggestions
                read -rp "Nhập tên model: " custom_model
                if [[ -n "$custom_model" ]]; then
                    OLLAMA_MODEL="$custom_model"
                fi
            fi
        fi
    fi
}

print_model_suggestions() {
    echo ""
    echo -e "  ${CYAN}Gợi ý model:${NC}"
    echo ""
    echo "    Model              Params    RAM"
    echo "    ─────────────────  ────────  ────────"
    echo "    qwen2.5:7b         7B        ~5GB"
    echo "    qwen2.5:14b        14B       ~10GB"
    echo "    qwen2.5:32b        32B       ~20GB"
    echo "    llama3:8b          8B        ~5GB"
    echo "    llama3:70b         70B       ~40GB"
    echo "    gemma2:9b          9B        ~6GB"
    echo "    mistral:7b         7B        ~5GB"
    echo "    deepseek-r1:14b    14B       ~10GB"
    echo "    phi3:14b           14B       ~10GB"
    echo ""
}

# ============================================================
#  5. Pull model
# ============================================================
pull_model() {
    if ollama list 2>/dev/null | grep -q "${OLLAMA_MODEL%%:*}"; then
        log "Model $OLLAMA_MODEL đã có sẵn."
    else
        info "Đang pull model $OLLAMA_MODEL (có thể mất vài phút)..."
        ollama pull "$OLLAMA_MODEL"
        log "Model $OLLAMA_MODEL đã sẵn sàng."
    fi
}

# ============================================================
#  6. Test model
# ============================================================
test_model() {
    echo ""
    read -rp "Test model bằng 1 câu nhanh? [y/N]: " do_test
    if [[ "$do_test" =~ ^[yY]$ ]]; then
        info "Đang test $OLLAMA_MODEL..."
        ollama run "$OLLAMA_MODEL" "Xin chào, trả lời ngắn gọn trong 1 câu." 2>/dev/null || warn "Test thất bại."
    fi
}

# ============================================================
#  Main
# ============================================================
main() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         Ollama Deploy Script             ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""

    detect_os
    install_ollama
    start_ollama
    select_model
    pull_model
    test_model

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Ollama deploy hoàn tất!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  Server:  http://localhost:11434"
    echo "  Model:   $OLLAMA_MODEL"
    echo ""
    echo "  Lệnh hữu ích:"
    echo "    ollama list              # Xem model đã cài"
    echo "    ollama run $OLLAMA_MODEL # Chat trực tiếp"
    echo "    ollama pull <model>      # Tải model mới"
    echo "    ollama rm <model>        # Xóa model"
    echo ""
    echo "  Tiếp theo: chạy deploy.sh để cài OpenClaw + Telegram"
    echo ""
}

main "$@"
