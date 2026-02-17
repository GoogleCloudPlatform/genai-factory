import logging

from rich.logging import RichHandler

logging.getLogger("google_genai").setLevel(logging.WARNING)
logging.getLogger("httpx").setLevel(logging.WARNING)

logging.basicConfig(
    level=logging.INFO,
    handlers=[RichHandler(show_path=False, show_level=False)]
)
