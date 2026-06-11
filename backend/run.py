"""
Скрипт для запуска сервера
"""
import os
import uvicorn

if __name__ == "__main__":
    # Совпадает с lib/services/server_config.dart (на macOS порт 5000 часто занят AirPlay).
    port = int(os.environ.get("PORT", "5001"))
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=port,
        reload=False,  # reload=True вызывает PermissionError на Windows в sandbox
        log_level="info"
    )

