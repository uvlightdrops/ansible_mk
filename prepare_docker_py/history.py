from datetime import datetime
import os

HISTORY_PATH = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'docs', 'HISTORY.md'))


def append_entry(text: str):
    """Append a timestamped paragraph to the global HISTORY.md file."""
    ts = datetime.utcnow().isoformat() + 'Z'
    entry = f"## {ts}\n\n{text.strip()}\n\n"
    with open(HISTORY_PATH, 'a') as f:
        f.write(entry)
    return HISTORY_PATH

