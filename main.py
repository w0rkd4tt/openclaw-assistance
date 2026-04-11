import logging
from app.bot import create_bot

logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    level=logging.INFO,
)

logger = logging.getLogger(__name__)


def main() -> None:
    logger.info("Khởi động OpenClaw Assistant...")
    bot = create_bot()
    logger.info("Bot đang chạy. Nhấn Ctrl+C để dừng.")
    bot.run_polling()


if __name__ == "__main__":
    main()
