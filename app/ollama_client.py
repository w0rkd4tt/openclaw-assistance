import httpx
from app.config import OLLAMA_BASE_URL, OLLAMA_MODEL, SYSTEM_PROMPT


class OllamaClient:
    def __init__(self):
        self.base_url = OLLAMA_BASE_URL
        self.model = OLLAMA_MODEL
        # Lưu lịch sử hội thoại theo user_id
        self.conversations: dict[int, list[dict]] = {}

    def _get_history(self, user_id: int) -> list[dict]:
        if user_id not in self.conversations:
            self.conversations[user_id] = []
        return self.conversations[user_id]

    def clear_history(self, user_id: int) -> None:
        self.conversations.pop(user_id, None)

    async def chat(self, user_id: int, message: str) -> str:
        history = self._get_history(user_id)
        history.append({"role": "user", "content": message})

        # Giới hạn lịch sử để tránh quá tải context
        if len(history) > 20:
            history = history[-20:]
            self.conversations[user_id] = history

        messages = [{"role": "system", "content": SYSTEM_PROMPT}] + history

        try:
            async with httpx.AsyncClient(timeout=120.0) as client:
                response = await client.post(
                    f"{self.base_url}/api/chat",
                    json={
                        "model": self.model,
                        "messages": messages,
                        "stream": False,
                    },
                )
                response.raise_for_status()
                data = response.json()
                assistant_message = data["message"]["content"]
                history.append({"role": "assistant", "content": assistant_message})
                return assistant_message

        except httpx.ConnectError:
            return (
                "❌ Không thể kết nối đến Ollama. "
                "Hãy chắc chắn Ollama đang chạy (`ollama serve`)."
            )
        except httpx.TimeoutException:
            return "⏳ Model đang xử lý quá lâu. Hãy thử lại với câu hỏi ngắn hơn."
        except httpx.HTTPStatusError as e:
            return f"❌ Lỗi từ Ollama: {e.response.status_code} - {e.response.text}"
        except Exception as e:
            return f"❌ Lỗi không xác định: {e}"
