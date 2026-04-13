#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  HuggingFace Model → Ollama Deploy Script
#  Tải GGUF từ HuggingFace, tạo Modelfile, import vào Ollama
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

# ============================================================
#  Preset models phổ biến trên HuggingFace
# ============================================================
declare -A PRESETS_REPO
declare -A PRESETS_FILE
declare -A PRESETS_TEMPLATE
declare -A PRESETS_DESC

# --- Qwen2.5 abliterated ---
PRESETS_REPO[qwen2.5-14b-abliterated]="huihui-ai/Qwen2.5-14B-Instruct-abliterated-v2-GGUF"
PRESETS_FILE[qwen2.5-14b-abliterated]="qwen2.5-14b-instruct-abliterated-v2.Q4_K_M.gguf"
PRESETS_TEMPLATE[qwen2.5-14b-abliterated]="chatml"
PRESETS_DESC[qwen2.5-14b-abliterated]="Qwen2.5 14B Instruct Abliterated v2 (uncensored, Q4_K_M ~9GB)"

PRESETS_REPO[qwen2.5-7b-abliterated]="huihui-ai/Qwen2.5-7B-Instruct-abliterated-v2-GGUF"
PRESETS_FILE[qwen2.5-7b-abliterated]="qwen2.5-7b-instruct-abliterated-v2.Q4_K_M.gguf"
PRESETS_TEMPLATE[qwen2.5-7b-abliterated]="chatml"
PRESETS_DESC[qwen2.5-7b-abliterated]="Qwen2.5 7B Instruct Abliterated v2 (uncensored, Q4_K_M ~5GB)"

PRESETS_REPO[qwen2.5-32b-abliterated]="huihui-ai/Qwen2.5-32B-Instruct-abliterated-v2-GGUF"
PRESETS_FILE[qwen2.5-32b-abliterated]="qwen2.5-32b-instruct-abliterated-v2.Q4_K_M.gguf"
PRESETS_TEMPLATE[qwen2.5-32b-abliterated]="chatml"
PRESETS_DESC[qwen2.5-32b-abliterated]="Qwen2.5 32B Instruct Abliterated v2 (uncensored, Q4_K_M ~19GB)"

# --- DeepSeek ---
PRESETS_REPO[deepseek-r1-14b-abliterated]="huihui-ai/DeepSeek-R1-Distill-Qwen-14B-abliterated-v2-GGUF"
PRESETS_FILE[deepseek-r1-14b-abliterated]="DeepSeek-R1-Distill-Qwen-14B-abliterated-v2.Q4_K_M.gguf"
PRESETS_TEMPLATE[deepseek-r1-14b-abliterated]="chatml"
PRESETS_DESC[deepseek-r1-14b-abliterated]="DeepSeek R1 Distill Qwen 14B Abliterated v2 (Q4_K_M ~9GB)"

# --- Llama 3 ---
PRESETS_REPO[llama3-8b-abliterated]="mlabonne/Meta-Llama-3.1-8B-Instruct-abliterated-GGUF"
PRESETS_FILE[llama3-8b-abliterated]="meta-llama-3.1-8b-instruct-abliterated.Q4_K_M.gguf"
PRESETS_TEMPLATE[llama3-8b-abliterated]="llama3"
PRESETS_DESC[llama3-8b-abliterated]="Llama 3.1 8B Instruct Abliterated (Q4_K_M ~5GB)"

# --- Mistral ---
PRESETS_REPO[mistral-7b-abliterated]="huihui-ai/Mistral-7B-Instruct-v0.3-abliterated-v3-GGUF"
PRESETS_FILE[mistral-7b-abliterated]="mistral-7b-instruct-v0.3-abliterated-v3.Q4_K_M.gguf"
PRESETS_TEMPLATE[mistral-7b-abliterated]="mistral"
PRESETS_DESC[mistral-7b-abliterated]="Mistral 7B Instruct Abliterated v3 (Q4_K_M ~4GB)"

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
    local tmpl_type="$1"
    case "$tmpl_type" in
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
#  1. Kiểm tra prerequisites
# ============================================================
check_prerequisites() {
    info "Kiểm tra prerequisites..."

    # Python + pip
    if ! command -v python3 &>/dev/null; then
        err "python3 chưa được cài. Hãy cài Python 3 trước."
    fi

    # huggingface-cli
    if ! command -v huggingface-cli &>/dev/null; then
        info "Cài đặt huggingface-hub..."
        pip install -q huggingface-hub
        if ! command -v huggingface-cli &>/dev/null; then
            # Thử qua python module
            python3 -m pip install -q huggingface-hub
        fi
    fi
    log "huggingface-cli sẵn sàng."

    # Ollama
    if ! command -v ollama &>/dev/null; then
        err "Ollama chưa cài. Chạy ./deploy-ollama.sh trước."
    fi

    # Ollama server
    if ! curl -sf http://localhost:11434/api/tags &>/dev/null; then
        warn "Ollama server chưa chạy. Đang khởi động..."
        ollama serve &
        for i in {1..15}; do
            curl -sf http://localhost:11434/api/tags &>/dev/null && break
            sleep 1
            [[ $i -eq 15 ]] && err "Ollama server không khởi động được."
        done
    fi
    log "Ollama server đang chạy."

    mkdir -p "$MODELS_DIR"
    log "Thư mục model: $MODELS_DIR"
}

# ============================================================
#  2. Chọn model
# ============================================================
select_model() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          HuggingFace → Ollama Model Importer                    ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  Preset models:${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    local idx=1
    for key in "${PRESET_KEYS[@]}"; do
        printf "    ${BOLD}%d)${NC} %s\n" "$idx" "${PRESETS_DESC[$key]}"
        idx=$((idx + 1))
    done
    echo ""
    echo -e "    ${BOLD}${idx})${NC} Nhập custom repo từ HuggingFace"
    echo ""

    read -rp "Chọn [1-$idx]: " choice

    if [[ -z "$choice" || ! "$choice" =~ ^[0-9]+$ ]]; then
        err "Lựa chọn không hợp lệ."
    fi

    if [[ "$choice" -ge 1 && "$choice" -le "${#PRESET_KEYS[@]}" ]]; then
        local key="${PRESET_KEYS[$((choice - 1))]}"
        HF_REPO="${PRESETS_REPO[$key]}"
        HF_FILE="${PRESETS_FILE[$key]}"
        TEMPLATE_TYPE="${PRESETS_TEMPLATE[$key]}"
        MODEL_NAME="$key"
        log "Đã chọn: ${PRESETS_DESC[$key]}"
    elif [[ "$choice" -eq "$idx" ]]; then
        select_custom_model
    else
        err "Lựa chọn không hợp lệ."
    fi
}

# ============================================================
#  2b. Custom model input
# ============================================================
select_custom_model() {
    echo ""
    echo -e "  ${CYAN}Nhập thông tin HuggingFace repo:${NC}"
    echo -e "  ${DIM}Ví dụ: huihui-ai/Qwen2.5-14B-Instruct-abliterated-v2-GGUF${NC}"
    echo ""
    read -rp "  HF Repo (user/repo): " HF_REPO
    [[ -z "$HF_REPO" ]] && err "Repo không được để trống."

    # Liệt kê các file GGUF trong repo
    echo ""
    info "Đang tìm file GGUF trong $HF_REPO..."
    local gguf_files
    gguf_files=$(huggingface-cli repo info "$HF_REPO" 2>/dev/null \
        | grep -oE '[^ ]+\.gguf' \
        || python3 -c "
from huggingface_hub import list_repo_files
files = [f for f in list_repo_files('$HF_REPO') if f.endswith('.gguf')]
for f in files:
    print(f)
" 2>/dev/null || true)

    if [[ -n "$gguf_files" ]]; then
        echo ""
        echo -e "  ${CYAN}File GGUF có sẵn:${NC}"
        echo ""
        local fidx=1
        local file_list=()
        while IFS= read -r f; do
            file_list+=("$f")
            # Hiện kích thước ước tính từ tên file
            local size_hint=""
            if echo "$f" | grep -qiE "q4_k_m"; then size_hint="${DIM}(recommended)${NC}"; fi
            printf "    ${BOLD}%d)${NC} %s %b\n" "$fidx" "$f" "$size_hint"
            fidx=$((fidx + 1))
        done <<< "$gguf_files"
        echo ""
        read -rp "  Chọn file [1-$((fidx-1))]: " file_choice

        if [[ -n "$file_choice" && "$file_choice" =~ ^[0-9]+$ && "$file_choice" -ge 1 && "$file_choice" -lt "$fidx" ]]; then
            HF_FILE="${file_list[$((file_choice - 1))]}"
        else
            err "Lựa chọn không hợp lệ."
        fi
    else
        warn "Không tìm thấy file GGUF tự động."
        read -rp "  Nhập tên file GGUF: " HF_FILE
        [[ -z "$HF_FILE" ]] && err "Tên file không được để trống."
    fi

    # Template
    echo ""
    echo -e "  ${CYAN}Chọn chat template:${NC}"
    echo "    1) ChatML (Qwen, DeepSeek, Yi, ...)"
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

    # Model name
    echo ""
    local default_name
    default_name=$(echo "$HF_FILE" | sed 's/\.gguf$//' | sed 's/\.Q[0-9].*$//' | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
    read -rp "  Tên model trong Ollama [default: $default_name]: " MODEL_NAME
    MODEL_NAME="${MODEL_NAME:-$default_name}"

    log "Custom model: $HF_REPO / $HF_FILE → $MODEL_NAME"
}

# ============================================================
#  3. Chọn quantization (cho preset)
# ============================================================
select_quantization() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  Chọn quantization:${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "    1) ${BOLD}Q4_K_M${NC} — Cân bằng chất lượng/tốc độ ${GREEN}(recommended)${NC}"
    echo -e "    2) Q5_K_M — Chất lượng cao hơn, chậm hơn"
    echo -e "    3) Q8_0   — Gần full precision, cần nhiều RAM"
    echo -e "    4) Q3_K_M — Nhẹ nhất, chất lượng thấp hơn"
    echo -e "    5) Giữ nguyên file đã chọn"
    echo ""
    read -rp "  Chọn [1-5, default=1]: " quant_choice

    case "${quant_choice:-1}" in
        1) HF_FILE=$(echo "$HF_FILE" | sed -E 's/Q[0-9][^.]*\.gguf/Q4_K_M.gguf/') ;;
        2) HF_FILE=$(echo "$HF_FILE" | sed -E 's/Q[0-9][^.]*\.gguf/Q5_K_M.gguf/') ;;
        3) HF_FILE=$(echo "$HF_FILE" | sed -E 's/Q[0-9][^.]*\.gguf/Q8_0.gguf/') ;;
        4) HF_FILE=$(echo "$HF_FILE" | sed -E 's/Q[0-9][^.]*\.gguf/Q3_K_M.gguf/') ;;
        5) ;; # giữ nguyên
    esac

    log "Quantization: $HF_FILE"
}

# ============================================================
#  4. Download model
# ============================================================
download_model() {
    local dest="$MODELS_DIR/$HF_FILE"

    if [[ -f "$dest" ]]; then
        log "File đã tồn tại: $dest"
        read -rp "Tải lại? [y/N]: " redownload
        if [[ ! "$redownload" =~ ^[yY]$ ]]; then
            return
        fi
    fi

    echo ""
    info "Đang tải $HF_FILE từ $HF_REPO..."
    info "Lưu vào: $MODELS_DIR/"
    echo ""

    if command -v huggingface-cli &>/dev/null; then
        huggingface-cli download "$HF_REPO" "$HF_FILE" --local-dir "$MODELS_DIR"
    else
        python3 -c "
from huggingface_hub import hf_hub_download
hf_hub_download(
    repo_id='$HF_REPO',
    filename='$HF_FILE',
    local_dir='$MODELS_DIR'
)
print('Download complete')
"
    fi

    if [[ ! -f "$dest" ]]; then
        err "Download thất bại. File không tồn tại: $dest"
    fi

    local size
    size=$(du -h "$dest" | awk '{print $1}')
    log "Download hoàn tất: $dest ($size)"
}

# ============================================================
#  5. Tạo Modelfile & import vào Ollama
# ============================================================
create_ollama_model() {
    local modelfile="$MODELS_DIR/Modelfile.$MODEL_NAME"
    local gguf_path="$MODELS_DIR/$HF_FILE"

    info "Tạo Modelfile cho $MODEL_NAME..."

    # System prompt
    echo ""
    local default_system="Bạn là OpenClaw Assistant, một trợ lý AI thông minh và thân thiện."
    read -rp "System prompt [Enter = default]: " custom_system
    local system_prompt="${custom_system:-$default_system}"

    # Ghi Modelfile
    {
        echo "FROM $gguf_path"
        echo ""
        echo "PARAMETER temperature 0.7"
        echo "PARAMETER top_p 0.9"
        echo "PARAMETER num_ctx 32768"
        echo ""
        get_template "$TEMPLATE_TYPE"
        echo ""
        echo "SYSTEM \"$system_prompt\""
    } > "$modelfile"

    log "Modelfile: $modelfile"

    # Kiểm tra model đã tồn tại trong Ollama
    if ollama list 2>/dev/null | grep -q "$MODEL_NAME"; then
        warn "Model $MODEL_NAME đã tồn tại trong Ollama."
        read -rp "Ghi đè? [y/N]: " overwrite
        if [[ ! "$overwrite" =~ ^[yY]$ ]]; then
            log "Giữ model cũ."
            return
        fi
    fi

    info "Import model vào Ollama (có thể mất vài phút)..."
    ollama create "$MODEL_NAME" -f "$modelfile"
    log "Model $MODEL_NAME đã được tạo trong Ollama."
}

# ============================================================
#  6. Test model
# ============================================================
test_model() {
    echo ""
    read -rp "Test model ngay? [Y/n]: " do_test
    if [[ "$do_test" =~ ^[nN]$ ]]; then
        return
    fi

    info "Testing $MODEL_NAME..."
    echo ""
    ollama run "$MODEL_NAME" "Xin chào, hãy giới thiệu ngắn gọn về bạn trong 2 câu." 2>/dev/null || warn "Test thất bại."
    echo ""

    # Hiện GPU status
    info "Trạng thái model:"
    ollama ps 2>/dev/null || true
    echo ""
}

# ============================================================
#  7. Set default cho OpenClaw
# ============================================================
set_openclaw_default() {
    if ! command -v openclaw &>/dev/null; then
        return
    fi

    echo ""
    read -rp "Set $MODEL_NAME làm model mặc định cho OpenClaw? [Y/n]: " set_default
    if [[ "$set_default" =~ ^[nN]$ ]]; then
        return
    fi

    local cfg_path="${OPENCLAW_HOME:-$HOME/.openclaw}/openclaw.json"
    if [[ -f "$cfg_path" ]]; then
        python3 -c "
import json
with open('$cfg_path') as f:
    cfg = json.load(f)
# Update model trong provider
if 'models' in cfg and 'providers' in cfg['models'] and 'ollama' in cfg['models']['providers']:
    provider = cfg['models']['providers']['ollama']
    if 'models' in provider and len(provider['models']) > 0:
        provider['models'][0]['id'] = '$MODEL_NAME'
        provider['models'][0]['name'] = '$MODEL_NAME'
    else:
        provider['models'] = [{
            'id': '$MODEL_NAME',
            'name': '$MODEL_NAME',
            'reasoning': False,
            'input': ['text'],
            'cost': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0},
            'contextWindow': 32768,
            'maxTokens': 32768
        }]
# Update agent default model
cfg.setdefault('agents', {}).setdefault('defaults', {})['model'] = {'primary': 'ollama/$MODEL_NAME'}
with open('$cfg_path', 'w') as f:
    json.dump(cfg, f, indent=2)
print('OpenClaw config updated')
" 2>/dev/null && log "OpenClaw default model: ollama/$MODEL_NAME" \
              || warn "Không thể cập nhật OpenClaw config."
    else
        warn "OpenClaw config không tìm thấy tại $cfg_path"
    fi
}

# ============================================================
#  8. Summary
# ============================================================
print_summary() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}${BOLD}  Import hoàn tất!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  Model:       $MODEL_NAME"
    echo "  Source:      $HF_REPO"
    echo "  File:        $HF_FILE"
    echo "  Template:    $TEMPLATE_TYPE"
    echo ""
    echo "  Lệnh hữu ích:"
    echo -e "    ${CYAN}ollama run $MODEL_NAME${NC}                    # Chat trực tiếp"
    echo -e "    ${CYAN}ollama ps${NC}                                  # Xem GPU/CPU status"
    echo -e "    ${CYAN}ollama rm $MODEL_NAME${NC}                     # Xóa model"
    echo -e "    ${CYAN}openclaw models set ollama/$MODEL_NAME${NC}    # Set cho OpenClaw"
    echo ""
}

# ============================================================
#  Main
# ============================================================
main() {
    check_prerequisites
    select_model
    select_quantization
    download_model
    create_ollama_model
    test_model
    set_openclaw_default
    print_summary
}

main "$@"
