"""Shared URL checks: no private/loopback hosts, no credentialed URLs."""
from __future__ import annotations

import ipaddress
import socket
from urllib.parse import urlparse


def is_private_or_local_host(host: str) -> bool:
    normalized = (host or "").strip().lower()
    if not normalized:
        return True
    if normalized in {"localhost", "127.0.0.1", "::1", "0.0.0.0"}:
        return True
    if normalized.endswith(".local") or normalized.endswith(".internal"):
        return True
    if normalized.endswith(".localhost"):
        return True
    try:
        ip = ipaddress.ip_address(normalized)
        return any(
            (
                ip.is_private,
                ip.is_loopback,
                ip.is_link_local,
                ip.is_multicast,
                ip.is_reserved,
                ip.is_unspecified,
            )
        )
    except ValueError:
        return False


def host_resolves_to_blocked_ip(host: str) -> bool:
    try:
        infos = socket.getaddrinfo(host, None)
    except socket.gaierror:
        return True
    for info in infos:
        ip_str = info[4][0]
        try:
            ip = ipaddress.ip_address(ip_str)
        except ValueError:
            continue
        if (
            ip.is_private
            or ip.is_loopback
            or ip.is_link_local
            or ip.is_multicast
            or ip.is_reserved
            or ip.is_unspecified
            or str(ip) == "169.254.169.254"
        ):
            return True
    return False


def parse_http_url(url: str) -> tuple[str, str]:
    parsed = urlparse((url or "").strip())
    if parsed.scheme not in ("http", "https"):
        raise ValueError("Разрешены только ссылки http/https")
    host = (parsed.hostname or "").lower()
    if not host:
        raise ValueError("Неверная ссылка")
    if parsed.username or parsed.password:
        raise ValueError("Учётные данные в ссылке запрещены")
    return parsed.geturl(), host


def require_public_http_url(url: str, *, https_only: bool = False) -> str:
    clean, host = parse_http_url(url)
    parsed = urlparse(clean)
    if https_only and parsed.scheme != "https":
        raise ValueError("Разрешён только https")
    if is_private_or_local_host(host) or host_resolves_to_blocked_ip(host):
        raise ValueError("Этот адрес недоступен")
    return clean
