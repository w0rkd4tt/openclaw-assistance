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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

    if [[ "$OS" == "linux" ]]; then
        # Cài các tool cần thiết (lsof cho openclaw gateway diagnostics)
        local pkgs_needed=()
        command -v curl &>/dev/null || pkgs_needed+=(curl)
        command -v lsof &>/dev/null || pkgs_needed+=(lsof)
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
    log "Node.js $(node -v)"

    # npm
    if ! command -v npm &>/dev/null; then
        err "npm không tìm thấy. Hãy cài Node.js trước."
    fi
    log "npm $(npm -v)"
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
#  4. Khởi động Ollama & chọn/pull model
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

    # Liệt kê model đã có
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
                echo ""
                echo -e "  ${CYAN}Gợi ý:${NC}"
                echo "    qwen2.5:32b      (32B, cần ~20GB RAM)"
                echo "    qwen2.5:14b      (14B, cần ~10GB RAM)"
                echo "    qwen2.5:7b       (7B,  cần ~5GB RAM)"
                echo "    llama3:8b        (8B,  cần ~5GB RAM)"
                echo "    llama3:70b       (70B, cần ~40GB RAM)"
                echo "    gemma2:9b        (9B,  cần ~6GB RAM)"
                echo "    mistral:7b       (7B,  cần ~5GB RAM)"
                echo "    deepseek-r1:14b  (14B, cần ~10GB RAM)"
                echo "    phi3:14b         (14B, cần ~10GB RAM)"
                echo ""
                read -rp "Nhập tên model: " custom_model
                if [[ -n "$custom_model" ]]; then
                    OLLAMA_MODEL="$custom_model"
                fi
            fi
        fi
    fi

    # Pull model nếu chưa có
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
    sudo npm install -g openclaw@latest
    log "OpenClaw $(openclaw --version 2>/dev/null || echo 'installed')."
}

# ============================================================
#  6. Cấu hình Telegram + Ollama cho OpenClaw
# ============================================================
configure_openclaw() {
    OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
    OPENCLAW_ENV="$OPENCLAW_HOME/.env"
    OPENCLAW_CONFIG="$OPENCLAW_HOME/openclaw.json"

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

        if [[ -z "$TELEGRAM_TOKEN" ]]; then
            err "Token không được để trống."
        fi

        {
            echo "# OpenClaw Environment"
            echo "TELEGRAM_BOT_TOKEN=$TELEGRAM_TOKEN"
            echo "OLLAMA_BASE_URL=http://localhost:11434"
            echo "OLLAMA_MODEL=$OLLAMA_MODEL"
        } >> "$OPENCLAW_ENV"

        log "Đã lưu cấu hình vào $OPENCLAW_ENV"
    fi

    # --- Xóa config cũ nếu có key không hợp lệ ---
    if [[ -f "$OPENCLAW_CONFIG" ]] && grep -q '"llm"' "$OPENCLAW_CONFIG"; then
        warn "Phát hiện config cũ có key không hợp lệ. Backup và tạo lại..."
        mv "$OPENCLAW_CONFIG" "$OPENCLAW_CONFIG.bak.$(date +%s)"
    fi

    # --- Tạo config mới nếu chưa có ---
    if [[ ! -f "$OPENCLAW_CONFIG" ]]; then
        echo '{}' > "$OPENCLAW_CONFIG"
        chmod 600 "$OPENCLAW_CONFIG"
    fi

    # --- Cấu hình qua CLI ---
    info "Cấu hình OpenClaw..."

    # Gateway mode (bắt buộc, nếu thiếu gateway sẽ không start)
    openclaw config set gateway.mode local 2>/dev/null || true

    # Telegram: bật + cho phép mọi người chat (dmPolicy open)
    openclaw config set channels.telegram.enabled true 2>/dev/null || true
    openclaw config set channels.telegram.dmPolicy open 2>/dev/null || true
    # allowFrom: ["*"] cần thiết khi dmPolicy=open
    openclaw config set 'channels.telegram.allowFrom' '["*"]' 2>/dev/null || true

    # Tắt memory search (không cần embedding provider cho Ollama local)
    openclaw config set agents.defaults.memorySearch.enabled false 2>/dev/null || true

    # Set model qua openclaw models set
    if curl -sf http://127.0.0.1:11434/api/tags &>/dev/null; then
        openclaw models set "ollama/$OLLAMA_MODEL" 2>/dev/null || true
        log "Agent model: ollama/$OLLAMA_MODEL"
    else
        warn "Ollama chưa chạy, bỏ qua set model. Chạy sau: openclaw models set ollama/$OLLAMA_MODEL"
    fi

    # --- Verify gateway.mode không bị mất ---
    if ! grep -q '"mode"' "$OPENCLAW_CONFIG" 2>/dev/null; then
        warn "gateway.mode bị mất sau config set, ghi trực tiếp..."
        local tmp
        tmp=$(mktemp)
        python3 -c "
import json, sys
with open('$OPENCLAW_CONFIG') as f:
    cfg = json.load(f)
cfg.setdefault('gateway', {})['mode'] = 'local'
cfg.setdefault('channels', {}).setdefault('telegram', {}).update({
    'enabled': True,
    'dmPolicy': 'open',
    'allowFrom': ['*']
})
cfg.setdefault('agents', {}).setdefault('defaults', {}).setdefault('memorySearch', {})['enabled'] = False
with open('$tmp', 'w') as f:
    json.dump(cfg, f, indent=2)
" && mv "$tmp" "$OPENCLAW_CONFIG"
        chmod 600 "$OPENCLAW_CONFIG"
        log "Config đã được ghi trực tiếp."
    fi

    # --- Validate config ---
    if openclaw config validate &>/dev/null; then
        log "Config hợp lệ."
    else
        warn "Config có thể chưa hoàn chỉnh, nhưng gateway vẫn có thể chạy."
    fi

    log "Cấu hình OpenClaw hoàn tất: $OPENCLAW_CONFIG"
}

# ============================================================
#  7. Cấu hình bot đơn giản (fallback nếu không dùng OpenClaw)
# ============================================================
setup_local_bot() {
    local LOCAL_ENV="$SCRIPT_DIR/.env"

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

        # Đảm bảo python3 có sẵn
        if ! command -v python3 &>/dev/null; then
            warn "python3 chưa được cài. Đang cài đặt..."
            if [[ "$OS" == "linux" ]]; then
                sudo apt-get update -qq
                sudo apt-get install -y python3 python3-venv python3-pip
            else
                brew install python3
            fi
        fi

        # Trên Debian/Ubuntu, cần python3-venv riêng
        if [[ "$OS" == "linux" ]] && ! python3 -m venv --help &>/dev/null; then
            warn "python3-venv chưa được cài. Đang cài đặt..."
            sudo apt-get update -qq
            sudo apt-get install -y python3-venv python3-pip
        fi

        # Tạo venv nếu chưa có hoặc bị lỗi
        if [[ ! -f "$SCRIPT_DIR/.venv/bin/activate" ]]; then
            rm -rf "$SCRIPT_DIR/.venv"
            info "Tạo Python venv tại $SCRIPT_DIR/.venv..."
            if ! python3 -m venv "$SCRIPT_DIR/.venv"; then
                err "Không tạo được venv. Hãy cài python3-venv: sudo apt install python3-venv"
            fi
        fi

        if [[ ! -f "$SCRIPT_DIR/.venv/bin/activate" ]]; then
            err "venv được tạo nhưng thiếu activate script. Hãy xóa $SCRIPT_DIR/.venv và chạy lại."
        fi

        # shellcheck disable=SC1091
        source "$SCRIPT_DIR/.venv/bin/activate"
        pip install -q --upgrade pip
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
            info "Khởi động OpenClaw gateway (foreground)..."
            echo ""
            echo -e "  ${YELLOW}Nhấn Ctrl+C để dừng gateway${NC}"
            echo ""
            # Chạy foreground - ổn định hơn systemd service
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
            echo "    openclaw gateway        # OpenClaw gateway (foreground)"
            echo "    python main.py          # Bot đơn giản"
            echo ""
            echo "  Hoặc cài systemd service:"
            echo "    openclaw gateway install"
            echo "    openclaw gateway start"
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
