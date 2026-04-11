import logging
from telegram import Update
from telegram.ext import (
    Application,
    CommandHandler,
    MessageHandler,
    ContextTypes,
    filters,
)
from app.config import TELEGRAM_BOT_TOKEN
from app.ollama_client import OllamaClient

logger = logging.getLogger(__name__)

ollama = OllamaClient()


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text(
        "🤖 Xin chào! Tôi là OpenClaw Assistant.\n\n"
        "Gửi tin nhắn bất kỳ để trò chuyện với tôi.\n\n"
        "Lệnh:\n"
        "/clear - Xóa lịch sử hội thoại\n"
        "/model - Xem model đang sử dụng"
    )


async def clear(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    ollama.clear_history(update.effective_user.id)
    await update.message.reply_text("🧹 Đã xóa lịch sử hội thoại.")


async def model_info(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text(
        f"🧠 Model: {ollama.model}\n"
        f"🔗 Ollama: {ollama.base_url}"
    )


async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    user_message = update.message.text

    # Gửi "đang gõ..." trong khi chờ model trả lời
    await update.message.chat.send_action("typing")

    reply = await ollama.chat(user_id, user_message)

    # Telegram giới hạn 4096 ký tự mỗi tin nhắn
    if len(reply) <= 4096:
        await update.message.reply_text(reply)
    else:
        for i in range(0, len(reply), 4096):
            await update.message.reply_text(reply[i : i + 4096])


def create_bot() -> Application:
    if not TELEGRAM_BOT_TOKEN:
        raise ValueError(
            "TELEGRAM_BOT_TOKEN chưa được cấu hình. "
            "Hãy tạo file .env với token từ @BotFather."
        )

    app = Application.builder().token(TELEGRAM_BOT_TOKEN).build()

    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("clear", clear))
    app.add_handler(CommandHandler("model", model_info))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))

    return app
