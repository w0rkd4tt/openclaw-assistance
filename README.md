# OpenClaw Assistant

Telegram bot trò chuyện AI sử dụng model local qua Ollama (mặc định: `qwen2.5:32b`).

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

## Cấu trúc

```
openclaw-assistance/
├── main.py              # Entry point
├── app/
│   ├── config.py        # Cấu hình (env vars)
│   ├── ollama_client.py # Giao tiếp với Ollama API
│   └── bot.py           # Telegram bot handlers
├── .env.example         # Mẫu biến môi trường
└── requirements.txt     # Dependencies
```

## Cài đặt

### 1. Cài Ollama

```bash
# macOS
brew install ollama

# Hoặc tải từ https://ollama.com
```

### 2. Pull model

```bash
ollama pull qwen2.5:32b
```

### 3. Chạy Ollama

```bash
ollama serve
```

### 4. Tạo Telegram Bot

- Mở Telegram, tìm **@BotFather**
- Gửi `/newbot` và làm theo hướng dẫn
- Copy token nhận được

### 5. Cấu hình project

```bash
cp .env.example .env
# Sửa .env, điền TELEGRAM_BOT_TOKEN
```

### 6. Cài dependencies và chạy

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python main.py
```

## Sử dụng

- `/start` - Bắt đầu trò chuyện
- `/clear` - Xóa lịch sử hội thoại
- `/model` - Xem model đang sử dụng
- Gửi tin nhắn bất kỳ để chat với AI

## Đổi model

Sửa `OLLAMA_MODEL` trong file `.env`:

```
OLLAMA_MODEL=llama3:8b
```
