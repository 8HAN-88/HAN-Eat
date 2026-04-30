#!/usr/bin/env python3
"""
Скрипт для создания базы данных и запуска миграций
"""
import os
import sys
from pathlib import Path

# Добавляем backend в путь
backend_path = Path(__file__).parent / "backend"
sys.path.insert(0, str(backend_path))

try:
    from sqlalchemy import create_engine, text
    from app.core.config import settings
except ImportError as e:
    print(f"Error importing modules: {e}")
    print("Make sure you're in the project root and dependencies are installed")
    sys.exit(1)

def create_database():
    """Создает базу данных haneat, если её нет"""
    # Получаем DATABASE_URL из настроек
    db_url = settings.DATABASE_URL
    
    # Парсим URL для получения имени базы данных
    # Формат: postgresql://user:password@host:port/database
    if "postgresql://" not in db_url:
        print("Error: DATABASE_URL must be a PostgreSQL URL")
        return False
    
    # Извлекаем имя базы данных
    db_name = db_url.split("/")[-1].split("?")[0]
    
    # Создаем URL для подключения к postgres (системная база)
    # Убираем имя базы из URL
    base_url = "/".join(db_url.split("/")[:-1])
    postgres_url = f"{base_url}/postgres"
    
    print(f"Connecting to PostgreSQL...")
    print(f"Database name: {db_name}")
    
    try:
        # Подключаемся к системной базе postgres
        engine = create_engine(postgres_url, isolation_level="AUTOCOMMIT")
        
        with engine.connect() as conn:
            # Проверяем, существует ли база данных
            result = conn.execute(
                text("SELECT 1 FROM pg_database WHERE datname = :db_name"),
                {"db_name": db_name}
            )
            
            if result.fetchone():
                print(f"✅ Database '{db_name}' already exists")
                return True
            else:
                # Создаем базу данных
                print(f"Creating database '{db_name}'...")
                conn.execute(text(f'CREATE DATABASE "{db_name}"'))
                print(f"✅ Database '{db_name}' created successfully")
                return True
                
    except Exception as e:
        print(f"❌ Error creating database: {e}")
        return False

def run_migrations():
    """Запускает миграции Alembic"""
    print("\n" + "="*50)
    print("Running database migrations...")
    print("="*50)
    
    os.chdir(backend_path)
    
    try:
        import subprocess
        result = subprocess.run(
            ["alembic", "upgrade", "head"],
            capture_output=True,
            text=True
        )
        
        if result.returncode == 0:
            print("✅ Migrations completed successfully")
            print(result.stdout)
            return True
        else:
            print("❌ Migration failed:")
            print(result.stderr)
            return False
            
    except FileNotFoundError:
        print("❌ Error: alembic not found")
        print("Install it with: pip install alembic")
        return False
    except Exception as e:
        print(f"❌ Error running migrations: {e}")
        return False

def main():
    print("="*50)
    print("Database Setup Script")
    print("="*50)
    print()
    
    # Проверяем, что .env файл существует
    env_file = backend_path / ".env"
    if not env_file.exists():
        print("❌ Error: backend/.env file not found")
        print("Please create it with DATABASE_URL configured")
        return 1
    
    print("✅ Found backend/.env file")
    print()
    
    # Создаем базу данных
    if not create_database():
        return 1
    
    # Запускаем миграции
    if not run_migrations():
        return 1
    
    print()
    print("="*50)
    print("✅ Database setup complete!")
    print("="*50)
    print()
    print("You can now start the backend server:")
    print("  cd backend")
    print("  python run.py")
    print()
    
    return 0

if __name__ == "__main__":
    sys.exit(main())

