import os
from dotenv import load_dotenv

load_dotenv()

TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "qwen2.5:32b")

SYSTEM_PROMPT = (
    "Bạn là OpenClaw Assistant, một trợ lý AI thông minh và thân thiện. "
    "Bạn trả lời bằng tiếng Việt khi người dùng hỏi tiếng Việt, "
    "và bằng tiếng Anh khi người dùng hỏi tiếng Anh. "
    "Hãy trả lời ngắn gọn, chính xác và hữu ích."
)
