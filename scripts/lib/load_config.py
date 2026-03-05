"""Shared config helper for brave-bot Python scripts.

Usage:
    from lib.load_config import load_config, get_config

    config = load_config()               # auto-discovers config.json
    org = get_config(config, "project.org", default="brave")
    repo = get_config(config, "project.prRepository", default="brave/brave-core")
"""

import json
import os


def load_config(config_path=None):
    """Load config.json, falling back to config.example.json.

    If config_path is None, searches relative to the bot repo root
    (derived from this file's location: lib/ -> scripts/ -> repo root).
    """
    if config_path and os.path.exists(config_path):
        with open(config_path) as f:
            return json.load(f)

    bot_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    for name in ("config.json", "config.example.json"):
        path = os.path.join(bot_dir, name)
        if os.path.exists(path):
            with open(path) as f:
                return json.load(f)

    return {}


def get_config(config, dotted_key, default=None):
    """Read a dotted key from the config dict (e.g. 'project.org')."""
    keys = dotted_key.split(".")
    value = config
    for key in keys:
        if isinstance(value, dict):
            value = value.get(key)
        else:
            return default
        if value is None:
            return default
    return value
