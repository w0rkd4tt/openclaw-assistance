# OpenClaw Assistant

Telegram bot trò chuyện AI sử dụng model local qua Ollama (mặc định: `qwen2.5:32b`).
Có 2 chế độ: **OpenClaw gateway** (đầy đủ tính năng) hoặc **bot Python đơn giản**.

## Quick Start

```bash
# Bước 1: Deploy Ollama + pull model
./deploy-ollama.sh

# Bước 2: Deploy OpenClaw + Telegram
./deploy.sh
```

Hoặc chỉ định model:

```bash
OLLAMA_MODEL=llama3:8b ./deploy-ollama.sh
OLLAMA_MODEL=llama3:8b ./deploy.sh
```

## Deploy Scripts

| Script | Mục đích |
|--------|----------|
| `deploy-ollama.sh` | Cài Ollama, khởi động server, chọn & pull model |
| `deploy.sh` | Cài OpenClaw, cấu hình Telegram + Ollama, khởi động gateway |

### deploy-ollama.sh

- Cài Ollama (brew trên macOS, install script trên Linux)
- Khởi động Ollama server
- Liệt kê model đã có, cho phép chọn hoặc nhập model mới
- Pull model nếu chưa có
- Test model bằng 1 câu nhanh (tùy chọn)

### deploy.sh

- Kiểm tra Ollama đã chạy (tự gọi `deploy-ollama.sh` nếu chưa)
- Cài Node.js, lsof (Linux)
- Cài OpenClaw (`npm install -g openclaw`)
- Hỏi Telegram Bot Token (từ @BotFather)
- Set `OLLAMA_API_KEY`, `gateway.mode`, `dmPolicy`, model
- Cài Python venv + dependencies (cho bot đơn giản)
- Chọn chạy: OpenClaw gateway hoặc bot Python

## Kiến trúc hệ thống

```mermaid
flowchart TB
    subgraph Telegram["Telegram Cloud"]
        BotFather["@BotFather\nCấp Token"]
        TGApi["Telegram Bot API"]
    end

    subgraph App["OpenClaw Assistant"]
        Main["main.py\nEntry Point"]
        Config["config.py\n• TELEGRAM_BOT_TOKEN\n• OLLAMA_BASE_URL\n• OLLAMA_MODEL\n• SYSTEM_PROMPT"]
        BotHandler["bot.py\n• /start - Chào mừng\n• /clear - Xóa history\n• /model - Xem model\n• text - Chat với AI"]
        Client["ollama_client.py\n• Quản lý history/user\n• Gọi Ollama API\n• Xử lý lỗi"]
        Memory["In-Memory Store\nconversations per user"]
    end

    subgraph Local["Local Machine"]
        Ollama["Ollama Server\nlocalhost:11434"]
        Model["qwen2.5:32b\nLLM Model"]
    end

    ENV[".env"] -.->|load| Config
    BotFather -.->|token| ENV
    Main -->|khởi tạo| BotHandler
    Config -.->|cấu hình| BotHandler
    Config -.->|cấu hình| Client
    BotHandler -->|polling| TGApi
    BotHandler -->|chat request| Client
    Client -->|lưu/đọc| Memory
    Client -->|HTTP POST /api/chat| Ollama
    Ollama -->|inference| Model
```

## Flow hoạt động

```mermaid
sequenceDiagram
    actor User as User
    participant TG as Telegram
    participant Bot as Bot Handler (bot.py)
    participant OC as OllamaClient
    participant History as Conversation History
    participant Ollama as Ollama Server
    participant LLM as qwen2.5:32b

    User->>TG: Gửi tin nhắn
    TG->>Bot: Polling nhận Update
    Bot->>TG: send_action("typing")
    TG->>User: "đang gõ..."

    Bot->>OC: chat(user_id, message)
    OC->>History: Lưu message vào history
    OC->>History: Trim nếu > 20 messages
    OC->>OC: Ghép [system_prompt] + history

    OC->>Ollama: POST /api/chat {model, messages}
    Ollama->>LLM: Inference
    LLM-->>Ollama: Generated response
    Ollama-->>OC: JSON {message: {content}}

    OC->>History: Lưu assistant response
    OC-->>Bot: Trả về response text

    alt Response <= 4096 ký tự
        Bot->>TG: reply_text(response)
    else Response > 4096 ký tự
        Bot->>TG: Chia chunks và gửi nhiều tin
    end

    TG-->>User: Hiển thị câu trả lời
```

## Xử lý commands

```mermaid
flowchart LR
    MSG["Tin nhắn từ User"] --> IS_CMD{Là command?}

    IS_CMD -->|/start| START["Gửi lời chào\n+ hướng dẫn"]
    IS_CMD -->|/clear| CLEAR["Xóa history\ncủa user"]
    IS_CMD -->|/model| MODEL["Hiện tên model\n+ Ollama URL"]
    IS_CMD -->|Text thường| CHAT["handle_message()"]

    CHAT --> TYPING["Hiện 'đang gõ...'"]
    TYPING --> CALL["ollama.chat()"]
    CALL --> REPLY["Gửi response\nvề Telegram"]
```

## Cấu trúc project

```
openclaw-assistance/
├── deploy-ollama.sh     # Deploy Ollama + model
├── deploy.sh            # Deploy OpenClaw + Telegram
├── main.py              # Entry point (bot đơn giản)
├── app/
│   ├── config.py        # Cấu hình (env vars)
│   ├── ollama_client.py # Giao tiếp với Ollama API
│   └── bot.py           # Telegram bot handlers
├── .env.example         # Mẫu biến môi trường
└── requirements.txt     # Python dependencies
```

## Cài đặt thủ công

<details>
<summary>Nếu không dùng deploy scripts</summary>

### 1. Cài Ollama

```bash
# macOS
brew install ollama

# Linux
curl -fsSL https://ollama.com/install.sh | sh
```

### 2. Pull model & chạy

```bash
ollama pull qwen2.5:32b
ollama serve
```

### 3. Tạo Telegram Bot

- Mở Telegram, tìm **@BotFather**
- Gửi `/newbot` và làm theo hướng dẫn
- Copy token nhận được

### 4. Chạy bot đơn giản (Python)

```bash
cp .env.example .env
# Sửa .env, điền TELEGRAM_BOT_TOKEN

python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python main.py
```

### 5. Hoặc chạy OpenClaw gateway

```bash
sudo npm install -g openclaw@latest
export OLLAMA_API_KEY=ollama-local
export TELEGRAM_BOT_TOKEN=your_token_here
openclaw config set gateway.mode local
openclaw config set channels.telegram.enabled true
openclaw config set channels.telegram.dmPolicy open
openclaw models set ollama/qwen2.5:32b
openclaw gateway
```

</details>

## Sử dụng trên Telegram

- `/start` - Bắt đầu trò chuyện
- `/clear` - Xóa lịch sử hội thoại
- `/model` - Xem model đang sử dụng
- Gửi tin nhắn bất kỳ để chat với AI

## Đổi model

```bash
OLLAMA_MODEL=llama3:8b ./deploy-ollama.sh   # Pull model mới
openclaw models set ollama/llama3:8b         # Đổi model OpenClaw
```
