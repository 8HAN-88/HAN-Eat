"""Human-readable device labels for auth sessions."""
from __future__ import annotations


def platform_from_user_agent(user_agent: str | None) -> str | None:
    ua = (user_agent or "").lower()
    if not ua:
        return None
    if "iphone" in ua or "ipad" in ua or "ipod" in ua:
        return "ios"
    if "android" in ua:
        return "android"
    if "mac os" in ua or "macintosh" in ua:
        return "macos"
    if "windows" in ua or "linux" in ua or "cros" in ua:
        return "web"
    return None


def label_from_user_agent(user_agent: str | None) -> str | None:
    ua = (user_agent or "").strip()
    if not ua:
        return None
    low = ua.lower()
    if "edg/" in low:
        browser = "Edge"
    elif "opr/" in low or "opera" in low:
        browser = "Opera"
    elif "firefox" in low or "fxios" in low:
        browser = "Firefox"
    elif "crios" in low or ("chrome" in low and "chromium" not in low):
        browser = "Chrome"
    elif "safari" in low:
        browser = "Safari"
    else:
        browser = "Браузер"

    if "iphone" in low:
        system = "iPhone"
    elif "ipad" in low:
        system = "iPad"
    elif "android" in low:
        system = "Android"
    elif "mac os" in low or "macintosh" in low:
        system = "Mac"
    elif "windows" in low:
        system = "Windows"
    elif "cros" in low:
        system = "ChromeOS"
    elif "linux" in low:
        system = "Linux"
    else:
        system = None

    if system:
        return f"{browser} · {system}"
    return browser


def display_device_name(
    *,
    device_name: str | None,
    device_platform: str | None,
    user_agent: str | None,
) -> str:
    name = (device_name or "").strip()
    if name:
        return name
    from_ua = label_from_user_agent(user_agent)
    if from_ua:
        return from_ua
    platform = (device_platform or "").strip().lower()
    labels = {
        "web": "Браузер",
        "ios": "iPhone",
        "android": "Android",
        "macos": "Mac",
    }
    if platform in labels:
        return labels[platform]
    if platform:
        return f"Устройство · {platform}"
    return "Браузер"


def display_device_platform(
    *,
    device_platform: str | None,
    user_agent: str | None,
) -> str | None:
    platform = (device_platform or "").strip() or None
    if platform:
        return platform
    return platform_from_user_agent(user_agent)
