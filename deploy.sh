#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  OpenClaw + Telegram — Deploy Script
#  Cài OpenClaw, cấu hình Telegram + Ollama, khởi động gateway
#  Yêu cầu: Ollama đã cài và đang chạy (dùng deploy-ollama.sh)
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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
OPENCLAW_ENV="$OPENCLAW_HOME/.env"
OPENCLAW_CONFIG="$OPENCLAW_HOME/openclaw.json"

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
#  2. Kiểm tra prerequisites
# ============================================================
check_prerequisites() {
    info "Kiểm tra prerequisites..."

    # Cài lsof trên Linux (cần cho gateway diagnostics)
    if [[ "$OS" == "linux" ]]; then
        local pkgs_needed=()
        command -v curl  &>/dev/null || pkgs_needed+=(curl)
        command -v lsof  &>/dev/null || pkgs_needed+=(lsof)
        if [[ ${#pkgs_needed[@]} -gt 0 ]]; then
            sudo apt-get update -qq
            sudo apt-get install -y "${pkgs_needed[@]}"
        fi
    fi

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
    log "Node.js $(node -v), npm $(npm -v)"

    # Ollama
    if ! command -v ollama &>/dev/null; then
        warn "Ollama chưa cài. Chạy deploy-ollama.sh trước."
        read -rp "Chạy deploy-ollama.sh ngay? [Y/n]: " run_ollama
        if [[ ! "$run_ollama" =~ ^[nN]$ ]]; then
            bash "$SCRIPT_DIR/deploy-ollama.sh"
        else
            err "Ollama là bắt buộc. Hãy chạy: ./deploy-ollama.sh"
        fi
    fi

    # Kiểm tra Ollama server đang chạy
    if ! curl -sf http://localhost:11434/api/tags &>/dev/null; then
        warn "Ollama server chưa chạy. Đang khởi động..."
        if [[ "$OS" == "macos" ]]; then
            open -a Ollama 2>/dev/null || ollama serve &
        else
            ollama serve &
        fi
        for i in {1..30}; do
            curl -sf http://localhost:11434/api/tags &>/dev/null && break
            sleep 1
            [[ $i -eq 30 ]] && err "Ollama server không khởi động được."
        done
    fi
    log "Ollama server đang chạy."

    # Detect model từ Ollama nếu chưa chỉ định
    local first_model
    first_model=$(ollama list 2>/dev/null | tail -n +2 | head -1 | awk '{print $1}' || true)
    if [[ -n "$first_model" && "$OLLAMA_MODEL" == "qwen2.5:32b" ]]; then
        OLLAMA_MODEL="$first_model"
    fi
    log "Model Ollama: $OLLAMA_MODEL"
}

# ============================================================
#  3. Cài đặt OpenClaw
# ============================================================
install_openclaw() {
    if command -v openclaw &>/dev/null; then
        log "OpenClaw đã có sẵn."
        return
    fi

    info "Cài đặt OpenClaw..."
    sudo npm install -g openclaw@latest
    log "OpenClaw $(openclaw --version 2>/dev/null || echo 'installed')."
}

# ============================================================
#  4. Cấu hình OpenClaw
# ============================================================
configure_openclaw() {
    mkdir -p "$OPENCLAW_HOME"
    chmod 700 "$OPENCLAW_HOME"

    # --- Telegram token ---
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
        [[ -z "$TELEGRAM_TOKEN" ]] && err "Token không được để trống."

        {
            echo "# OpenClaw Environment"
            echo "TELEGRAM_BOT_TOKEN=$TELEGRAM_TOKEN"
            echo "OLLAMA_BASE_URL=http://localhost:11434"
            echo "OLLAMA_MODEL=$OLLAMA_MODEL"
        } >> "$OPENCLAW_ENV"
        log "Đã lưu token vào $OPENCLAW_ENV"
    fi

    # --- OLLAMA_API_KEY (bắt buộc để OpenClaw nhận Ollama provider) ---
    if [[ -f "$OPENCLAW_ENV" ]] && grep -q "OLLAMA_API_KEY" "$OPENCLAW_ENV"; then
        log "OLLAMA_API_KEY đã có."
    else
        echo 'OLLAMA_API_KEY=ollama-local' >> "$OPENCLAW_ENV"
        log "Đã thêm OLLAMA_API_KEY vào $OPENCLAW_ENV"
    fi

    # --- Xóa config cũ nếu có key không hợp lệ ---
    if [[ -f "$OPENCLAW_CONFIG" ]] && grep -q '"llm"' "$OPENCLAW_CONFIG"; then
        warn "Config cũ có key không hợp lệ. Backup và tạo lại..."
        mv "$OPENCLAW_CONFIG" "$OPENCLAW_CONFIG.bak.$(date +%s)"
    fi

    # --- Tạo config nếu chưa có ---
    if [[ ! -f "$OPENCLAW_CONFIG" ]]; then
        echo '{}' > "$OPENCLAW_CONFIG"
        chmod 600 "$OPENCLAW_CONFIG"
    fi

    # --- Cấu hình qua CLI ---
    info "Cấu hình OpenClaw..."

    # Load env để CLI nhận OLLAMA_API_KEY
    set -a
    # shellcheck disable=SC1090
    source "$OPENCLAW_ENV"
    set +a

    openclaw config set gateway.mode local                          2>/dev/null || true
    openclaw config set channels.telegram.enabled true              2>/dev/null || true
    openclaw config set channels.telegram.dmPolicy open             2>/dev/null || true
    openclaw config set 'channels.telegram.allowFrom' '["*"]'      2>/dev/null || true
    openclaw config set agents.defaults.memorySearch.enabled false  2>/dev/null || true

    # Set model
    openclaw models set "ollama/$OLLAMA_MODEL" 2>/dev/null || true
    log "Agent model: ollama/$OLLAMA_MODEL"

    # --- Fallback: ghi trực tiếp nếu gateway.mode bị mất ---
    if ! grep -q '"mode"' "$OPENCLAW_CONFIG" 2>/dev/null; then
        warn "gateway.mode bị mất, ghi trực tiếp..."
        python3 -c "
import json
with open('$OPENCLAW_CONFIG') as f:
    cfg = json.load(f)
cfg.setdefault('gateway', {})['mode'] = 'local'
cfg.setdefault('channels', {}).setdefault('telegram', {}).update({
    'enabled': True, 'dmPolicy': 'open', 'allowFrom': ['*']
})
cfg.setdefault('agents', {}).setdefault('defaults', {}).setdefault('memorySearch', {})['enabled'] = False
cfg.setdefault('agents', {}).setdefault('defaults', {})['model'] = {'primary': 'ollama/$OLLAMA_MODEL'}
with open('$OPENCLAW_CONFIG', 'w') as f:
    json.dump(cfg, f, indent=2)
"
        chmod 600 "$OPENCLAW_CONFIG"
    fi

    # Validate
    if openclaw config validate &>/dev/null; then
        log "Config hợp lệ."
    else
        warn "Config có thể chưa hoàn chỉnh, gateway vẫn sẽ cố chạy."
    fi

    log "Cấu hình hoàn tất: $OPENCLAW_CONFIG"
}

# ============================================================
#  5. Setup bot đơn giản (Python, fallback)
# ============================================================
setup_local_bot() {
    local LOCAL_ENV="$SCRIPT_DIR/.env"

    # Copy env
    if [[ ! -f "$LOCAL_ENV" ]] && [[ -f "$OPENCLAW_ENV" ]]; then
        cp "$OPENCLAW_ENV" "$LOCAL_ENV"
        log "Đã copy .env từ OpenClaw."
    fi

    # Python venv + deps
    if [[ -f "$SCRIPT_DIR/requirements.txt" ]]; then
        info "Cài đặt Python dependencies..."

        if ! command -v python3 &>/dev/null; then
            if [[ "$OS" == "linux" ]]; then
                sudo apt-get update -qq
                sudo apt-get install -y python3 python3-venv python3-pip
            else
                brew install python3
            fi
        fi

        if [[ "$OS" == "linux" ]] && ! python3 -m venv --help &>/dev/null; then
            sudo apt-get update -qq
            sudo apt-get install -y python3-venv python3-pip
        fi

        if [[ ! -f "$SCRIPT_DIR/.venv/bin/activate" ]]; then
            rm -rf "$SCRIPT_DIR/.venv"
            python3 -m venv "$SCRIPT_DIR/.venv" || err "Không tạo được venv. Chạy: sudo apt install python3-venv"
        fi

        # shellcheck disable=SC1091
        source "$SCRIPT_DIR/.venv/bin/activate"
        pip install -q --upgrade pip
        pip install -q -r "$SCRIPT_DIR/requirements.txt"
        log "Python dependencies sẵn sàng."
    fi
}

# ============================================================
#  6. Khởi động
# ============================================================
start_services() {
    # Dừng gateway cũ nếu đang chạy
    if curl -sf http://127.0.0.1:18789/ &>/dev/null || \
       openclaw gateway status &>/dev/null 2>&1; then
        info "Dừng gateway cũ..."
        openclaw gateway stop 2>/dev/null || true
        sleep 2
    fi

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Deploy hoàn tất!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  Ollama:    http://localhost:11434"
    echo "  Model:     $OLLAMA_MODEL"
    echo "  OpenClaw:  $OPENCLAW_HOME/"
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
            echo -e "  ${YELLOW}Nhấn Ctrl+C để dừng${NC}"
            echo ""
            # Export env để gateway nhận OLLAMA_API_KEY
            set -a
            # shellcheck disable=SC1090
            source "$OPENCLAW_ENV"
            set +a
            openclaw gateway
            ;;
        2)
            info "Khởi động bot đơn giản..."
            # shellcheck disable=SC1091
            source "$SCRIPT_DIR/.venv/bin/activate"
            python "$SCRIPT_DIR/main.py"
            ;;
        3)
            echo ""
            log "Chạy sau bằng:"
            echo "    export OLLAMA_API_KEY=ollama-local"
            echo "    openclaw gateway        # OpenClaw gateway"
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
    echo -e "${CYAN}║   OpenClaw + Telegram Deploy             ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""

    detect_os
    check_prerequisites
    install_openclaw
    configure_openclaw
    setup_local_bot
    start_services
}

main "$@"
