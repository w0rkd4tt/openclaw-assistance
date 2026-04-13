#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  Unified Model Deploy Script
#  Tự động detect nguồn model:
#    - Ollama registry  → ollama pull
#    - HuggingFace repo → tải GGUF + tạo Modelfile + import
#    - File GGUF local  → tạo Modelfile + import
#  Hỗ trợ: macOS & Linux (bao gồm WSL2)
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

log()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[✗]${NC} $*"; exit 1; }
info()  { echo -e "${CYAN}[→]${NC} $*"; }

MODELS_DIR="${MODELS_DIR:-$HOME/models}"

# Biến global cho model đang xử lý
MODEL_SOURCE=""      # ollama | huggingface | local_gguf
MODEL_NAME=""        # Tên model trong Ollama
HF_REPO=""           # HuggingFace repo (user/repo)
HF_FILE=""           # Tên file GGUF
GGUF_PATH=""         # Đường dẫn đến file GGUF
TEMPLATE_TYPE=""     # chatml | llama3 | mistral

# ============================================================
#  Preset models HuggingFace
# ============================================================
declare -A PRESETS_REPO PRESETS_FILE PRESETS_TEMPLATE PRESETS_DESC

PRESETS_REPO[qwen2.5-14b-abliterated]="huihui-ai/Qwen2.5-14B-Instruct-abliterated-v2-GGUF"
PRESETS_FILE[qwen2.5-14b-abliterated]="qwen2.5-14b-instruct-abliterated-v2.Q4_K_M.gguf"
PRESETS_TEMPLATE[qwen2.5-14b-abliterated]="chatml"
PRESETS_DESC[qwen2.5-14b-abliterated]="Qwen2.5 14B Abliterated v2 (uncensored, ~9GB)"

PRESETS_REPO[qwen2.5-7b-abliterated]="huihui-ai/Qwen2.5-7B-Instruct-abliterated-v2-GGUF"
PRESETS_FILE[qwen2.5-7b-abliterated]="qwen2.5-7b-instruct-abliterated-v2.Q4_K_M.gguf"
PRESETS_TEMPLATE[qwen2.5-7b-abliterated]="chatml"
PRESETS_DESC[qwen2.5-7b-abliterated]="Qwen2.5 7B Abliterated v2 (uncensored, ~5GB)"

PRESETS_REPO[qwen2.5-32b-abliterated]="huihui-ai/Qwen2.5-32B-Instruct-abliterated-v2-GGUF"
PRESETS_FILE[qwen2.5-32b-abliterated]="qwen2.5-32b-instruct-abliterated-v2.Q4_K_M.gguf"
PRESETS_TEMPLATE[qwen2.5-32b-abliterated]="chatml"
PRESETS_DESC[qwen2.5-32b-abliterated]="Qwen2.5 32B Abliterated v2 (uncensored, ~19GB)"

PRESETS_REPO[deepseek-r1-14b-abliterated]="huihui-ai/DeepSeek-R1-Distill-Qwen-14B-abliterated-v2-GGUF"
PRESETS_FILE[deepseek-r1-14b-abliterated]="DeepSeek-R1-Distill-Qwen-14B-abliterated-v2.Q4_K_M.gguf"
PRESETS_TEMPLATE[deepseek-r1-14b-abliterated]="chatml"
PRESETS_DESC[deepseek-r1-14b-abliterated]="DeepSeek R1 14B Abliterated v2 (~9GB)"

PRESETS_REPO[llama3-8b-abliterated]="mlabonne/Meta-Llama-3.1-8B-Instruct-abliterated-GGUF"
PRESETS_FILE[llama3-8b-abliterated]="meta-llama-3.1-8b-instruct-abliterated.Q4_K_M.gguf"
PRESETS_TEMPLATE[llama3-8b-abliterated]="llama3"
PRESETS_DESC[llama3-8b-abliterated]="Llama 3.1 8B Abliterated (~5GB)"

PRESETS_REPO[mistral-7b-abliterated]="huihui-ai/Mistral-7B-Instruct-v0.3-abliterated-v3-GGUF"
PRESETS_FILE[mistral-7b-abliterated]="mistral-7b-instruct-v0.3-abliterated-v3.Q4_K_M.gguf"
PRESETS_TEMPLATE[mistral-7b-abliterated]="mistral"
PRESETS_DESC[mistral-7b-abliterated]="Mistral 7B Abliterated v3 (~4GB)"

PRESET_KEYS=(
    "qwen2.5-14b-abliterated"
    "qwen2.5-7b-abliterated"
    "qwen2.5-32b-abliterated"
    "deepseek-r1-14b-abliterated"
    "llama3-8b-abliterated"
    "mistral-7b-abliterated"
)

# ============================================================
#  Chat templates
# ============================================================
get_template() {
    case "$1" in
        chatml)
            cat <<'TMPL'
TEMPLATE """{{- if .System }}<|im_start|>system
{{ .System }}<|im_end|>
{{ end }}<|im_start|>user
{{ .Prompt }}<|im_end|>
<|im_start|>assistant
{{ .Response }}<|im_end|>"""
TMPL
            ;;
        llama3)
            cat <<'TMPL'
TEMPLATE """<|begin_of_text|>{{- if .System }}<|start_header_id|>system<|end_header_id|>

{{ .System }}<|eot_id|>{{ end }}<|start_header_id|>user<|end_header_id|>

{{ .Prompt }}<|eot_id|><|start_header_id|>assistant<|end_header_id|>

{{ .Response }}<|eot_id|>"""
TMPL
            ;;
        mistral)
            cat <<'TMPL'
TEMPLATE """[INST] {{- if .System }}{{ .System }}

{{ end }}{{ .Prompt }} [/INST]{{ .Response }}"""
TMPL
            ;;
        *)
            cat <<'TMPL'
TEMPLATE """{{- if .System }}<|im_start|>system
{{ .System }}<|im_end|>
{{ end }}<|im_start|>user
{{ .Prompt }}<|im_end|>
<|im_start|>assistant
{{ .Response }}<|im_end|>"""
TMPL
            ;;
    esac
}

# ============================================================
#  Detect OS & cài Ollama
# ============================================================
setup_ollama() {
    case "$(uname -s)" in
        Darwin) OS="macos" ;;
        Linux)  OS="linux" ;;
        *)      err "OS không được hỗ trợ: $(uname -s)" ;;
    esac
    log "Hệ điều hành: $OS ($(uname -m))"

    # Cài Ollama nếu chưa có
    if ! command -v ollama &>/dev/null; then
        info "Cài đặt Ollama..."
        if [[ "$OS" == "macos" ]]; then
            brew install ollama
        else
            command -v curl &>/dev/null || { sudo apt-get update -qq && sudo apt-get install -y curl; }
            curl -fsSL https://ollama.com/install.sh | sh
        fi
        log "Ollama đã cài xong."
    else
        log "Ollama: $(ollama -v 2>/dev/null || echo 'installed')"
    fi

    # Khởi động server
    if ! curl -sf http://localhost:11434/api/tags &>/dev/null; then
        info "Khởi động Ollama server..."
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
}

# ============================================================
#  Detect nguồn model từ input string
#  Trả về: MODEL_SOURCE (ollama | huggingface | local_gguf)
# ============================================================
detect_model_source() {
    local input="$1"

    # File GGUF local
    if [[ "$input" == *.gguf && -f "$input" ]]; then
        MODEL_SOURCE="local_gguf"
        GGUF_PATH="$input"
        MODEL_NAME=$(basename "$input" .gguf | sed 's/\.Q[0-9].*$//' | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
        TEMPLATE_TYPE="chatml"
        return
    fi

    # HuggingFace URL
    if [[ "$input" == *huggingface.co* || "$input" == *hf.co* ]]; then
        MODEL_SOURCE="huggingface"
        # Extract repo từ URL: https://huggingface.co/user/repo → user/repo
        HF_REPO=$(echo "$input" | sed -E 's|https?://(huggingface\.co\|hf\.co)/||' | sed 's|/tree/.*||' | sed 's|/$||')
        return
    fi

    # HuggingFace repo format: user/repo (có slash, không có dấu :)
    if [[ "$input" == */* && "$input" != *:* ]]; then
        MODEL_SOURCE="huggingface"
        HF_REPO="$input"
        return
    fi

    # Ollama registry: model:tag hoặc model
    MODEL_SOURCE="ollama"
    MODEL_NAME="$input"
}

# ============================================================
#  Menu chọn model chính
# ============================================================
select_model() {
    # Liệt kê model đã có
    local existing
    existing=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' || true)

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              Model Deploy (Ollama + HuggingFace)                 ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Model đã cài
    if [[ -n "$existing" ]]; then
        echo -e "${CYAN}  Model đã có trên máy:${NC}"
        echo -e "${DIM}$(echo "$existing" | sed 's/^/    /')${NC}"
        echo ""
    fi

    echo -e "${BOLD}  Nguồn model:${NC}"
    echo ""
    echo "    1) Ollama Registry  (qwen2.5:14b, llama3:8b, ...)"
    echo "    2) HuggingFace      (preset abliterated models)"
    echo "    3) HuggingFace      (nhập repo tùy chọn)"
    echo "    4) File GGUF local  (đã tải sẵn trên máy)"
    echo ""
    read -rp "Chọn nguồn [1-4]: " source_choice

    case "${source_choice:-1}" in
        1) select_ollama_model ;;
        2) select_hf_preset ;;
        3) select_hf_custom ;;
        4) select_local_gguf ;;
        *) err "Lựa chọn không hợp lệ." ;;
    esac
}

# ============================================================
#  Chọn model từ Ollama registry
# ============================================================
select_ollama_model() {
    MODEL_SOURCE="ollama"
    echo ""
    echo -e "  ${CYAN}Gợi ý model Ollama:${NC}"
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
    read -rp "  Nhập tên model: " input
    [[ -z "$input" ]] && err "Tên model không được để trống."
    detect_model_source "$input"
}

# ============================================================
#  Chọn HuggingFace preset
# ============================================================
select_hf_preset() {
    MODEL_SOURCE="huggingface"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  HuggingFace Presets:${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    local idx=1
    for key in "${PRESET_KEYS[@]}"; do
        printf "    ${BOLD}%d)${NC} %s\n" "$idx" "${PRESETS_DESC[$key]}"
        idx=$((idx + 1))
    done
    echo ""
    read -rp "  Chọn [1-${#PRESET_KEYS[@]}]: " choice

    if [[ -n "$choice" && "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le "${#PRESET_KEYS[@]}" ]]; then
        local key="${PRESET_KEYS[$((choice - 1))]}"
        HF_REPO="${PRESETS_REPO[$key]}"
        HF_FILE="${PRESETS_FILE[$key]}"
        TEMPLATE_TYPE="${PRESETS_TEMPLATE[$key]}"
        MODEL_NAME="$key"
        log "Đã chọn: ${PRESETS_DESC[$key]}"
    else
        err "Lựa chọn không hợp lệ."
    fi
}

# ============================================================
#  Nhập HuggingFace repo tùy chọn
# ============================================================
select_hf_custom() {
    MODEL_SOURCE="huggingface"
    echo ""
    echo -e "  ${DIM}Ví dụ: huihui-ai/Qwen2.5-14B-Instruct-abliterated-v2-GGUF${NC}"
    echo -e "  ${DIM}       https://huggingface.co/user/repo${NC}"
    echo ""
    read -rp "  HF Repo hoặc URL: " input
    [[ -z "$input" ]] && err "Repo không được để trống."
    detect_model_source "$input"

    # Nếu detect ra không phải HF → dùng nguyên input làm repo
    if [[ "$MODEL_SOURCE" != "huggingface" ]]; then
        MODEL_SOURCE="huggingface"
        HF_REPO="$input"
    fi
}

# ============================================================
#  Chọn file GGUF local
# ============================================================
select_local_gguf() {
    MODEL_SOURCE="local_gguf"
    echo ""

    # Tìm file GGUF trên máy
    local gguf_files
    gguf_files=$(find "$HOME" -maxdepth 4 -name "*.gguf" -type f 2>/dev/null | head -20 || true)

    if [[ -n "$gguf_files" ]]; then
        echo -e "  ${CYAN}File GGUF tìm thấy:${NC}"
        echo ""
        local idx=1
        local file_list=()
        while IFS= read -r f; do
            file_list+=("$f")
            local size
            size=$(du -h "$f" 2>/dev/null | awk '{print $1}')
            printf "    ${BOLD}%d)${NC} %s ${DIM}(%s)${NC}\n" "$idx" "$f" "$size"
            idx=$((idx + 1))
        done <<< "$gguf_files"
        echo "    $idx) Nhập đường dẫn khác"
        echo ""
        read -rp "  Chọn [1-$idx]: " choice

        if [[ -n "$choice" && "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -lt "$idx" ]]; then
            GGUF_PATH="${file_list[$((choice - 1))]}"
        elif [[ "$choice" -eq "$idx" ]]; then
            read -rp "  Đường dẫn file GGUF: " GGUF_PATH
        else
            err "Lựa chọn không hợp lệ."
        fi
    else
        read -rp "  Đường dẫn file GGUF: " GGUF_PATH
    fi

    [[ -z "$GGUF_PATH" ]] && err "Đường dẫn không được để trống."
    [[ ! -f "$GGUF_PATH" ]] && err "File không tồn tại: $GGUF_PATH"

    MODEL_NAME=$(basename "$GGUF_PATH" .gguf | sed 's/\.Q[0-9].*$//' | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
    TEMPLATE_TYPE="chatml"

    echo ""
    read -rp "  Tên model trong Ollama [default: $MODEL_NAME]: " custom_name
    MODEL_NAME="${custom_name:-$MODEL_NAME}"
}

# ============================================================
#  Cài huggingface-cli nếu cần
# ============================================================
ensure_hf_cli() {
    if command -v huggingface-cli &>/dev/null; then
        return
    fi

    # Kiểm tra nếu đã cài ở user level
    if python3 -c "import huggingface_hub" 2>/dev/null; then
        log "huggingface-hub đã cài (python module)."
        return
    fi

    info "Cài đặt huggingface-hub..."

    # Thử pipx trước (recommended cho externally-managed)
    if command -v pipx &>/dev/null; then
        pipx install huggingface-hub 2>/dev/null && { log "huggingface-cli sẵn sàng (pipx)."; return; }
    fi

    # Thử pip bình thường
    if pip install -q huggingface-hub 2>/dev/null; then
        log "huggingface-cli sẵn sàng."
        return
    fi

    # Thử pip --user
    if pip install -q --user huggingface-hub 2>/dev/null; then
        export PATH="$HOME/.local/bin:$PATH"
        log "huggingface-cli sẵn sàng (user install)."
        return
    fi

    # Fallback: --break-system-packages (Kali, Debian 12+, Ubuntu 24+)
    if pip install -q --break-system-packages huggingface-hub 2>/dev/null; then
        log "huggingface-cli sẵn sàng (break-system-packages)."
        return
    fi

    err "Không cài được huggingface-hub. Thử:\n  pipx install huggingface-hub\n  hoặc: pip install --user huggingface-hub"
}

# ============================================================
#  Tìm & chọn file GGUF từ HuggingFace repo
# ============================================================
resolve_hf_file() {
    # Nếu đã có file từ preset → skip
    [[ -n "${HF_FILE:-}" ]] && return

    ensure_hf_cli

    info "Đang tìm file GGUF trong $HF_REPO..."
    local gguf_files
    gguf_files=$(python3 -c "
from huggingface_hub import list_repo_files
files = [f for f in list_repo_files('$HF_REPO') if f.endswith('.gguf')]
for f in files:
    print(f)
" 2>/dev/null || true)

    if [[ -z "$gguf_files" ]]; then
        err "Không tìm thấy file GGUF nào trong $HF_REPO"
    fi

    echo ""
    echo -e "  ${CYAN}File GGUF có sẵn:${NC}"
    echo ""
    local idx=1
    local file_list=()
    while IFS= read -r f; do
        file_list+=("$f")
        local hint=""
        echo "$f" | grep -qiE "q4_k_m" && hint=" ${GREEN}(recommended)${NC}"
        printf "    ${BOLD}%d)${NC} %s%b\n" "$idx" "$f" "$hint"
        idx=$((idx + 1))
    done <<< "$gguf_files"
    echo ""
    read -rp "  Chọn file [1-$((idx-1))]: " choice

    if [[ -n "$choice" && "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -lt "$idx" ]]; then
        HF_FILE="${file_list[$((choice - 1))]}"
    else
        err "Lựa chọn không hợp lệ."
    fi

    # Tên model
    local default_name
    default_name=$(echo "$HF_FILE" | sed 's/\.gguf$//' | sed 's/\.Q[0-9].*$//' | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
    echo ""
    read -rp "  Tên model trong Ollama [default: $default_name]: " custom_name
    MODEL_NAME="${custom_name:-$default_name}"

    # Template
    select_template
}

# ============================================================
#  Chọn chat template
# ============================================================
select_template() {
    # Nếu đã set từ preset → skip
    [[ -n "${TEMPLATE_TYPE:-}" ]] && return

    echo ""
    echo -e "  ${CYAN}Chọn chat template:${NC}"
    echo "    1) ChatML  (Qwen, DeepSeek, Yi, ...)"
    echo "    2) Llama 3"
    echo "    3) Mistral"
    echo ""
    read -rp "  Template [1-3, default=1]: " tmpl_choice
    case "${tmpl_choice:-1}" in
        1) TEMPLATE_TYPE="chatml" ;;
        2) TEMPLATE_TYPE="llama3" ;;
        3) TEMPLATE_TYPE="mistral" ;;
        *) TEMPLATE_TYPE="chatml" ;;
    esac
}

# ============================================================
#  Chọn quantization
# ============================================================
select_quantization() {
    echo ""
    echo -e "${BOLD}  Quantization:${NC}"
    echo ""
    echo -e "    1) ${BOLD}Q4_K_M${NC} — Cân bằng chất lượng/tốc độ ${GREEN}(recommended)${NC}"
    echo -e "    2) Q5_K_M — Chất lượng cao hơn, chậm hơn"
    echo -e "    3) Q8_0   — Gần full precision, cần nhiều RAM"
    echo -e "    4) Q3_K_M — Nhẹ nhất, chất lượng thấp hơn"
    echo -e "    5) Giữ nguyên"
    echo ""
    read -rp "  Chọn [1-5, default=1]: " q
    case "${q:-1}" in
        1) HF_FILE=$(echo "$HF_FILE" | sed -E 's/Q[0-9][^.]*\.gguf/Q4_K_M.gguf/') ;;
        2) HF_FILE=$(echo "$HF_FILE" | sed -E 's/Q[0-9][^.]*\.gguf/Q5_K_M.gguf/') ;;
        3) HF_FILE=$(echo "$HF_FILE" | sed -E 's/Q[0-9][^.]*\.gguf/Q8_0.gguf/') ;;
        4) HF_FILE=$(echo "$HF_FILE" | sed -E 's/Q[0-9][^.]*\.gguf/Q3_K_M.gguf/') ;;
        5) ;;
    esac
    log "File: $HF_FILE"
}

# ============================================================
#  Download GGUF từ HuggingFace
# ============================================================
download_hf_model() {
    ensure_hf_cli
    mkdir -p "$MODELS_DIR"

    local dest="$MODELS_DIR/$HF_FILE"
    GGUF_PATH="$dest"

    if [[ -f "$dest" ]]; then
        local size
        size=$(du -h "$dest" | awk '{print $1}')
        log "File đã tồn tại: $dest ($size)"
        read -rp "Tải lại? [y/N]: " re
        [[ ! "$re" =~ ^[yY]$ ]] && return
    fi

    info "Đang tải $HF_FILE từ $HF_REPO..."
    huggingface-cli download "$HF_REPO" "$HF_FILE" --local-dir "$MODELS_DIR" \
        || python3 -c "
from huggingface_hub import hf_hub_download
hf_hub_download(repo_id='$HF_REPO', filename='$HF_FILE', local_dir='$MODELS_DIR')
" || err "Download thất bại."

    [[ ! -f "$dest" ]] && err "File không tồn tại sau download: $dest"
    local size
    size=$(du -h "$dest" | awk '{print $1}')
    log "Download hoàn tất ($size)"
}

# ============================================================
#  Import GGUF vào Ollama (tạo Modelfile + ollama create)
# ============================================================
import_gguf_to_ollama() {
    local modelfile="$MODELS_DIR/Modelfile.$MODEL_NAME"

    # System prompt
    echo ""
    local default_sys="Bạn là OpenClaw Assistant, một trợ lý AI thông minh và thân thiện."
    read -rp "System prompt [Enter = default]: " custom_sys
    local sys="${custom_sys:-$default_sys}"

    # Ghi Modelfile
    {
        echo "FROM $GGUF_PATH"
        echo ""
        echo "PARAMETER temperature 0.7"
        echo "PARAMETER top_p 0.9"
        echo "PARAMETER num_ctx 32768"
        echo ""
        get_template "$TEMPLATE_TYPE"
        echo ""
        echo "SYSTEM \"$sys\""
    } > "$modelfile"

    # Kiểm tra model cũ
    if ollama list 2>/dev/null | grep -q "$MODEL_NAME"; then
        warn "Model $MODEL_NAME đã tồn tại."
        read -rp "Ghi đè? [Y/n]: " ow
        [[ "$ow" =~ ^[nN]$ ]] && return
    fi

    info "Import vào Ollama..."
    ollama create "$MODEL_NAME" -f "$modelfile"
    log "Model $MODEL_NAME đã sẵn sàng."
}

# ============================================================
#  Pull model từ Ollama registry
# ============================================================
pull_ollama_model() {
    if ollama list 2>/dev/null | grep -q "${MODEL_NAME%%:*}"; then
        log "Model $MODEL_NAME đã có sẵn."
    else
        info "Đang pull $MODEL_NAME từ Ollama registry..."
        if ! ollama pull "$MODEL_NAME" 2>/dev/null; then
            warn "Không tìm thấy $MODEL_NAME trên Ollama registry."
            echo ""
            echo -e "  ${YELLOW}Có thể đây là model từ HuggingFace?${NC}"
            read -rp "  Thử tìm trên HuggingFace? [Y/n]: " try_hf
            if [[ ! "$try_hf" =~ ^[nN]$ ]]; then
                MODEL_SOURCE="huggingface"
                # Thử tìm repo GGUF dựa trên tên model
                local search_term="${MODEL_NAME%%:*}"
                HF_REPO=""
                HF_FILE=""
                echo ""
                echo -e "  ${DIM}Nhập repo HuggingFace cho model này:${NC}"
                read -rp "  HF Repo (user/repo): " HF_REPO
                [[ -z "$HF_REPO" ]] && err "Repo không được để trống."
                resolve_hf_file
                select_quantization
                download_hf_model
                import_gguf_to_ollama
                return
            else
                err "Model không tìm thấy."
            fi
        fi
        log "Model $MODEL_NAME đã sẵn sàng."
    fi
}

# ============================================================
#  Deploy model (router chính)
# ============================================================
deploy_model() {
    case "$MODEL_SOURCE" in
        ollama)
            pull_ollama_model
            ;;
        huggingface)
            resolve_hf_file
            select_quantization
            download_hf_model
            import_gguf_to_ollama
            ;;
        local_gguf)
            select_template
            import_gguf_to_ollama
            ;;
        *)
            err "Nguồn model không xác định: $MODEL_SOURCE"
            ;;
    esac
}

# ============================================================
#  Test model
# ============================================================
test_model() {
    echo ""
    read -rp "Test model ngay? [Y/n]: " do_test
    [[ "$do_test" =~ ^[nN]$ ]] && return

    info "Testing $MODEL_NAME..."
    echo ""
    ollama run "$MODEL_NAME" "Xin chào, hãy giới thiệu ngắn gọn về bạn trong 2 câu." 2>/dev/null \
        || warn "Test thất bại."
    echo ""
    info "Trạng thái:"
    ollama ps 2>/dev/null || true
}

# ============================================================
#  Set default cho OpenClaw (nếu có)
# ============================================================
set_openclaw_default() {
    command -v openclaw &>/dev/null || return

    echo ""
    read -rp "Set $MODEL_NAME làm model mặc định cho OpenClaw? [Y/n]: " sd
    [[ "$sd" =~ ^[nN]$ ]] && return

    local cfg="${OPENCLAW_HOME:-$HOME/.openclaw}/openclaw.json"
    [[ ! -f "$cfg" ]] && { warn "OpenClaw config không tìm thấy."; return; }

    python3 -c "
import json
with open('$cfg') as f:
    c = json.load(f)
p = c.setdefault('models',{}).setdefault('providers',{}).setdefault('ollama',{})
p['baseUrl'] = 'http://127.0.0.1:11434'
p['apiKey'] = 'ollama-local'
p['api'] = 'ollama'
p['models'] = [{'id':'$MODEL_NAME','name':'$MODEL_NAME','reasoning':False,'input':['text'],
    'cost':{'input':0,'output':0,'cacheRead':0,'cacheWrite':0},'contextWindow':32768,'maxTokens':32768}]
c.setdefault('agents',{}).setdefault('defaults',{})['model'] = {'primary':'ollama/$MODEL_NAME'}
with open('$cfg','w') as f:
    json.dump(c, f, indent=2)
print('Done')
" 2>/dev/null && log "OpenClaw default: ollama/$MODEL_NAME" \
              || warn "Không thể cập nhật OpenClaw config."
}

# ============================================================
#  Summary
# ============================================================
print_summary() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}${BOLD}  Deploy hoàn tất!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  Model:     $MODEL_NAME"
    [[ "$MODEL_SOURCE" == "huggingface" ]] && echo "  Source:    $HF_REPO"
    [[ "$MODEL_SOURCE" == "local_gguf" ]]  && echo "  Source:    $GGUF_PATH"
    [[ "$MODEL_SOURCE" == "ollama" ]]      && echo "  Source:    Ollama Registry"
    echo ""
    echo "  Lệnh:"
    echo -e "    ${CYAN}ollama run $MODEL_NAME${NC}"
    echo -e "    ${CYAN}ollama ps${NC}"
    echo ""
}

# ============================================================
#  Main
# ============================================================
main() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              Model Deploy Script                                ║${NC}"
    echo -e "${CYAN}║  Ollama Registry / HuggingFace / Local GGUF → Ollama            ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    setup_ollama

    # Nếu truyền argument → auto detect nguồn
    if [[ $# -gt 0 ]]; then
        detect_model_source "$1"
        log "Auto-detected: $MODEL_SOURCE"
        if [[ "$MODEL_SOURCE" == "huggingface" && -z "${HF_FILE:-}" ]]; then
            resolve_hf_file
            select_quantization
        fi
    else
        select_model
    fi

    deploy_model
    test_model
    set_openclaw_default
    print_summary
}

main "$@"
