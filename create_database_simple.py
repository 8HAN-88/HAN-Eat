#!/usr/bin/env python3
"""
Простой скрипт для создания базы данных
Читает DATABASE_URL напрямую из .env файла
"""
import os
import re
from pathlib import Path
from sqlalchemy import create_engine, text

def read_env_file():
    """Читает .env файл и возвращает словарь с переменными"""
    env_file = Path("backend/.env")
    if not env_file.exists():
        print("❌ Error: backend/.env file not found")
        return None
    
    env_vars = {}
    # Пробуем разные кодировки
    encodings = ['utf-8', 'utf-8-sig', 'cp1251', 'latin-1']
    content = None
    for encoding in encodings:
        try:
            with open(env_file, 'r', encoding=encoding) as f:
                content = f.read()
            break
        except UnicodeDecodeError:
            continue
    
    if content is None:
        print("❌ Error: Could not read .env file (encoding issue)")
        return None
    
    for line in content.splitlines():
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            key, value = line.split('=', 1)
            env_vars[key.strip()] = value.strip()
    
    return env_vars

def create_database():
    """Создает базу данных haneat"""
    env_vars = read_env_file()
    if not env_vars:
        return False
    
    db_url = env_vars.get('DATABASE_URL', '')
    if not db_url:
        print("❌ Error: DATABASE_URL not found in .env file")
        return False
    
    print(f"📋 DATABASE_URL: {db_url[:50]}...")
    
    # Парсим URL для получения имени базы данных
    # Формат: postgresql://user:password@host:port/database
    match = re.search(r'postgresql://[^/]+/([^?]+)', db_url)
    if not match:
        print("❌ Error: Invalid DATABASE_URL format")
        return False
    
    db_name = match.group(1)
    print(f"📋 Database name: {db_name}")
    
    # Создаем URL для подключения к postgres (системная база)
    # Заменяем имя базы на postgres
    postgres_url = re.sub(r'/([^/?]+)', '/postgres', db_url)
    
    print(f"\n🔌 Connecting to PostgreSQL...")
    
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
                print(f"📦 Creating database '{db_name}'...")
                conn.execute(text(f'CREATE DATABASE "{db_name}"'))
                print(f"✅ Database '{db_name}' created successfully!")
                return True
                
    except Exception as e:
        print(f"❌ Error: {e}")
        print("\n💡 Tips:")
        print("  - Make sure PostgreSQL service is running")
        print("  - Check that DATABASE_URL has correct password")
        print("  - Verify PostgreSQL is accessible on localhost:5432")
        return False

def run_migrations():
    """Запускает миграции Alembic"""
    print("\n" + "="*50)
    print("🔄 Running database migrations...")
    print("="*50)
    
    os.chdir("backend")
    
    try:
        import subprocess
        result = subprocess.run(
            ["alembic", "upgrade", "head"],
            capture_output=True,
            text=True
        )
        
        if result.returncode == 0:
            print("✅ Migrations completed successfully!")
            if result.stdout:
                print(result.stdout)
            return True
        else:
            print("❌ Migration failed:")
            if result.stderr:
                print(result.stderr)
            if result.stdout:
                print(result.stdout)
            return False
            
    except FileNotFoundError:
        print("❌ Error: alembic not found")
        print("💡 Install it with: pip install alembic")
        return False
    except Exception as e:
        print(f"❌ Error running migrations: {e}")
        return False
    finally:
        os.chdir("..")

def main():
    print("="*50)
    print("🗄️  Database Setup")
    print("="*50)
    print()
    
    # Проверяем .env файл
    env_file = Path("backend/.env")
    if not env_file.exists():
        print("❌ Error: backend/.env file not found")
        print("💡 Please create it with DATABASE_URL configured")
        return 1
    
    print("✅ Found backend/.env file")
    print()
    
    # Создаем базу данных
    if not create_database():
        return 1
    
    # Запускаем миграции
    if not run_migrations():
        print("\n⚠️  Migrations failed, but database was created")
        print("💡 You can run migrations manually:")
        print("   cd backend")
        print("   alembic upgrade head")
        return 1
    
    print()
    print("="*50)
    print("✅ Database setup complete!")
    print("="*50)
    print()
    print("🚀 You can now start the backend server:")
    print("   cd backend")
    print("   python run.py")
    print()
    
    return 0

if __name__ == "__main__":
    import sys
    sys.exit(main())

