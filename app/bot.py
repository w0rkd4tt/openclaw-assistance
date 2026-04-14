import asyncio
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


async def _keep_typing(chat, stop_event: asyncio.Event):
    """Gửi typing action liên tục cho đến khi có kết quả."""
    while not stop_event.is_set():
        try:
            await chat.send_action("typing")
        except Exception:
            pass
        try:
            await asyncio.wait_for(stop_event.wait(), timeout=4)
            break
        except asyncio.TimeoutError:
            continue


async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    user_message = update.message.text
    chat_type = update.message.chat.type

    # Trong group: chỉ phản hồi khi được mention hoặc reply
    if chat_type in ("group", "supergroup"):
        bot_username = context.bot.username
        is_mentioned = f"@{bot_username}" in user_message
        is_reply_to_bot = (
            update.message.reply_to_message
            and update.message.reply_to_message.from_user
            and update.message.reply_to_message.from_user.id == context.bot.id
        )
        if not is_mentioned and not is_reply_to_bot:
            return
        user_message = user_message.replace(f"@{bot_username}", "").strip()
        if not user_message:
            return

    # Gửi placeholder trước để tránh timeout
    placeholder = await update.message.reply_text("⏳ Đang xử lý...")

    # Typing indicator liên tục trong khi chờ Ollama
    stop_typing = asyncio.Event()
    typing_task = asyncio.create_task(
        _keep_typing(update.message.chat, stop_typing)
    )

    try:
        reply = await ollama.chat(user_id, user_message)
    finally:
        stop_typing.set()
        await typing_task

    # Sửa placeholder thành câu trả lời
    try:
        if len(reply) <= 4096:
            await placeholder.edit_text(reply)
        else:
            await placeholder.edit_text(reply[:4096])
            for i in range(4096, len(reply), 4096):
                await update.message.reply_text(reply[i : i + 4096])
    except Exception as e:
        logger.error("Lỗi gửi reply: %s", e)
        try:
            await update.message.reply_text(reply[:4096])
        except Exception:
            pass


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
