#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  OpenClaw + Ollama + Telegram — One-click Deploy Script
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
#  2. Cài đặt dependencies cơ bản
# ============================================================
install_prerequisites() {
    info "Kiểm tra dependencies..."

    # Node.js
    if ! command -v node &>/dev/null; then
        warn "Node.js chưa được cài. Đang cài đặt..."
        if [[ "$OS" == "macos" ]]; then
            brew install node
        else
            curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
            sudo apt-get install -y nodejs
        fi
    fi
    log "Node.js $(node -v)"

    # npm
    if ! command -v npm &>/dev/null; then
        err "npm không tìm thấy. Hãy cài Node.js trước."
    fi
    log "npm $(npm -v)"

    # curl
    if ! command -v curl &>/dev/null; then
        if [[ "$OS" == "linux" ]]; then
            sudo apt-get install -y curl
        else
            err "curl không tìm thấy."
        fi
    fi
}

# ============================================================
#  3. Cài đặt Ollama
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
        curl -fsSL https://ollama.com/install.sh | sh
    fi
    log "Ollama đã cài xong."
}

# ============================================================
#  4. Khởi động Ollama & pull model
# ============================================================
start_ollama_and_pull() {
    # Kiểm tra Ollama đang chạy chưa
    if ! curl -sf http://localhost:11434/api/tags &>/dev/null; then
        info "Khởi động Ollama server..."
        if [[ "$OS" == "macos" ]]; then
            open -a Ollama 2>/dev/null || ollama serve &
        else
            ollama serve &
        fi
        OLLAMA_PID=$!

        # Đợi server sẵn sàng
        for i in {1..30}; do
            if curl -sf http://localhost:11434/api/tags &>/dev/null; then
                break
            fi
            sleep 1
            if [[ $i -eq 30 ]]; then
                err "Ollama server không khởi động được sau 30s."
            fi
        done
        log "Ollama server đang chạy."
    else
        log "Ollama server đã chạy sẵn."
    fi

    # Pull model
    if ollama list 2>/dev/null | grep -q "${OLLAMA_MODEL%%:*}"; then
        log "Model $OLLAMA_MODEL đã có sẵn."
    else
        info "Đang pull model $OLLAMA_MODEL (có thể mất vài phút)..."
        ollama pull "$OLLAMA_MODEL"
        log "Model $OLLAMA_MODEL đã sẵn sàng."
    fi
}

# ============================================================
#  5. Cài đặt OpenClaw
# ============================================================
install_openclaw() {
    if command -v openclaw &>/dev/null; then
        log "OpenClaw đã có sẵn."
        return
    fi

    info "Cài đặt OpenClaw..."
    npm install -g openclaw@latest
    log "OpenClaw $(openclaw --version 2>/dev/null || echo 'installed')."
}

# ============================================================
#  6. Cấu hình Telegram + Ollama cho OpenClaw
# ============================================================
configure_openclaw() {
    OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
    OPENCLAW_ENV="$OPENCLAW_HOME/.env"

    mkdir -p "$OPENCLAW_HOME"

    # Hỏi Telegram token nếu chưa có
    if [[ -f "$OPENCLAW_ENV" ]] && grep -q "TELEGRAM_BOT_TOKEN" "$OPENCLAW_ENV"; then
        log "Telegram token đã được cấu hình."
    else
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}  Cấu hình Telegram Bot${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo "  1. Mở Telegram, tìm @BotFather"
        echo "  2. Gửi /newbot và làm theo hướng dẫn"
        echo "  3. Copy token nhận được"
        echo ""
        read -rp "Nhập Telegram Bot Token: " TELEGRAM_TOKEN

        if [[ -z "$TELEGRAM_TOKEN" ]]; then
            err "Token không được để trống."
        fi

        # Ghi vào .env
        {
            echo "# OpenClaw Environment"
            echo "TELEGRAM_BOT_TOKEN=$TELEGRAM_TOKEN"
            echo "OLLAMA_BASE_URL=http://localhost:11434"
            echo "OLLAMA_MODEL=$OLLAMA_MODEL"
        } >> "$OPENCLAW_ENV"

        log "Đã lưu cấu hình vào $OPENCLAW_ENV"
    fi

    # Tạo/cập nhật openclaw.json cho Ollama local
    OPENCLAW_CONFIG="$OPENCLAW_HOME/openclaw.json"
    if [[ ! -f "$OPENCLAW_CONFIG" ]]; then
        cat > "$OPENCLAW_CONFIG" <<JSONEOF
{
  "llm": {
    "provider": "ollama",
    "model": "$OLLAMA_MODEL",
    "baseUrl": "http://localhost:11434"
  },
  "channels": {
    "telegram": {
      "enabled": true
    }
  }
}
JSONEOF
        log "Đã tạo cấu hình OpenClaw: $OPENCLAW_CONFIG"
    else
        log "openclaw.json đã tồn tại, giữ nguyên."
    fi
}

# ============================================================
#  7. Cấu hình bot đơn giản (fallback nếu không dùng OpenClaw)
# ============================================================
setup_local_bot() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    LOCAL_ENV="$SCRIPT_DIR/.env"

    if [[ -f "$LOCAL_ENV" ]] && grep -q "TELEGRAM_BOT_TOKEN" "$LOCAL_ENV"; then
        log "File .env local đã có sẵn."
    else
        OPENCLAW_ENV="${OPENCLAW_HOME:-$HOME/.openclaw}/.env"
        if [[ -f "$OPENCLAW_ENV" ]]; then
            cp "$OPENCLAW_ENV" "$LOCAL_ENV"
            log "Đã copy cấu hình từ OpenClaw sang local .env"
        fi
    fi

    # Cài Python dependencies
    if [[ -f "$SCRIPT_DIR/requirements.txt" ]]; then
        info "Cài đặt Python dependencies..."
        if [[ ! -d "$SCRIPT_DIR/.venv" ]]; then
            python3 -m venv "$SCRIPT_DIR/.venv"
        fi
        source "$SCRIPT_DIR/.venv/bin/activate"
        pip install -q -r "$SCRIPT_DIR/requirements.txt"
        log "Python dependencies đã sẵn sàng."
    fi
}

# ============================================================
#  8. Khởi động
# ============================================================
start_services() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Deploy hoàn tất!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  Ollama:    http://localhost:11434"
    echo "  Model:     $OLLAMA_MODEL"
    echo "  OpenClaw:  ~/.openclaw/"
    echo ""
    echo -e "${CYAN}Chọn cách chạy:${NC}"
    echo "  1) OpenClaw gateway (đầy đủ tính năng)"
    echo "  2) Bot đơn giản (chỉ Telegram + Ollama)"
    echo "  3) Thoát (tự chạy sau)"
    echo ""
    read -rp "Lựa chọn [1/2/3]: " choice

    case "$choice" in
        1)
            info "Khởi động OpenClaw gateway..."
            openclaw onboard --install-daemon 2>/dev/null || openclaw start
            ;;
        2)
            SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            info "Khởi động bot đơn giản..."
            source "$SCRIPT_DIR/.venv/bin/activate"
            python "$SCRIPT_DIR/main.py"
            ;;
        3)
            echo ""
            log "Chạy sau bằng:"
            echo "    openclaw start          # OpenClaw gateway"
            echo "    python main.py          # Bot đơn giản"
            ;;
        *)
            warn "Lựa chọn không hợp lệ, thoát."
            ;;
    esac
}

# ============================================================
#  Main
# ============================================================
main() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║   OpenClaw + Ollama + Telegram Deploy    ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""

    detect_os
    install_prerequisites
    install_ollama
    start_ollama_and_pull
    install_openclaw
    configure_openclaw
    setup_local_bot
    start_services
}

main "$@"
