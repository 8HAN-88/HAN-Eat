"""Upload allowlist: messenger media stays, executables and active content do not."""
from __future__ import annotations

# Chat and posts need photos, video, voice, and ordinary documents.
# The block list is the "virus.exe" case: never store a runnable or HTML payload.
BLOCKED_EXTENSIONS = frozenset(
    {
        "exe",
        "dll",
        "bat",
        "cmd",
        "com",
        "msi",
        "scr",
        "ps1",
        "sh",
        "apk",
        "html",
        "htm",
        "svg",
        "js",
        "mjs",
        "jar",
        "vbs",
        "hta",
        "iso",
        "php",
        "phtml",
    }
)

BLOCKED_CONTENT_TYPES = frozenset(
    {
        "application/x-msdownload",
        "application/x-executable",
        "application/x-dosexec",
        "application/javascript",
        "text/javascript",
        "text/html",
        "image/svg+xml",
        "application/x-sh",
        "application/x-bat",
        "application/x-httpd-php",
    }
)

SAFE_DOCUMENT_EXTENSIONS = frozenset({"pdf", "txt", "doc", "docx", "zip"})

# Matches nginx client_max_body_size when MAX_VIDEO_SIZE_MB is left at 0.
DEFAULT_VIDEO_CAP_MB = 64


def filename_extension(filename: str | None) -> str:
    name = (filename or "").replace("\\", "/").rsplit("/", 1)[-1].strip().lower()
    if "." not in name:
        return ""
    return name.rsplit(".", 1)[-1]


def content_type_base(content_type: str | None) -> str:
    return (content_type or "").split(";", 1)[0].strip().lower()


def upload_block_reason(content_type: str | None, filename: str | None = None) -> str | None:
    """Return a short reason when the upload must be refused, else None."""
    ct = content_type_base(content_type)
    if ct in BLOCKED_CONTENT_TYPES:
        return "blocked content type"
    ext = filename_extension(filename)
    if ext in BLOCKED_EXTENSIONS:
        return "blocked file extension"
    if ct.startswith("image/") and ext in BLOCKED_EXTENSIONS:
        return "blocked file extension"
    return None


def document_octet_stream_allowed(content_type: str | None, filename: str | None) -> bool:
    """Generic binary is allowed only with an ordinary document name."""
    if content_type_base(content_type) != "application/octet-stream":
        return True
    return filename_extension(filename) in SAFE_DOCUMENT_EXTENSIONS


def video_cap_megabytes(configured_mb: int) -> int:
    """0 in config means 'use the nginx ceiling', not 'unlimited'."""
    if configured_mb and configured_mb > 0:
        return configured_mb
    return DEFAULT_VIDEO_CAP_MB
