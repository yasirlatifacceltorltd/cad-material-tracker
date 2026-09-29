#!/usr/bin/env bash
# ==============================================================================
# Script: setup_local_db.sh
# Purpose: Sets up a local PostgreSQL database (via Docker), updates .env,
#          runs Alembic migrations, seeds the initial user, and restarts services.
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "============================================================"
echo "🚀 Setting up Local PostgreSQL Database"
echo "============================================================"

# Database configuration
DB_USER="cad_user"
DB_PASSWORD="cad_password_123"
DB_NAME="cad_material_tracker"
DB_PORT="5432"
DB_HOST="127.0.0.1"
CONTAINER_NAME="cad-postgres"

DB_URL="postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}"

# Determine Docker command (with or without sudo)
if command -v docker &>/dev/null; then
    if docker info &>/dev/null; then
        DOCKER_CMD="docker"
    elif sudo docker info &>/dev/null; then
        DOCKER_CMD="sudo docker"
    else
        echo "⚠️ Docker is installed but daemon is not running. Starting Docker..."
        sudo systemctl start docker || true
        DOCKER_CMD="sudo docker"
    fi
else
    echo "❌ Docker is not installed. Please install Docker or run a local PostgreSQL service."
    exit 1
fi

echo "📦 Ensuring PostgreSQL container ($CONTAINER_NAME) is running..."

# Check if container already exists
if $DOCKER_CMD ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    if $DOCKER_CMD ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "✅ Container '$CONTAINER_NAME' is already running."
    else
        echo "🔄 Starting stopped container '$CONTAINER_NAME'..."
        $DOCKER_CMD start "$CONTAINER_NAME"
    fi
else
    echo "🐳 Creating and starting new container '$CONTAINER_NAME'..."
    $DOCKER_CMD run -d \
        --name "$CONTAINER_NAME" \
        -p "${DB_HOST}:${DB_PORT}:5432" \
        -e POSTGRES_USER="$DB_USER" \
        -e POSTGRES_PASSWORD="$DB_PASSWORD" \
        -e POSTGRES_DB="$DB_NAME" \
        -v cad_postgres_data:/var/lib/postgresql/data \
        --restart unless-stopped \
        postgres:15-alpine
fi

# Wait for PostgreSQL to be ready
echo "⏳ Waiting for PostgreSQL to be ready to accept connections..."
MAX_RETRIES=30
COUNT=0
until $DOCKER_CMD exec "$CONTAINER_NAME" pg_isready -U "$DB_USER" -d "$DB_NAME" &>/dev/null || [ $COUNT -eq $MAX_RETRIES ]; do
    sleep 1
    COUNT=$((COUNT + 1))
    echo -n "."
done
echo ""

if [ $COUNT -eq $MAX_RETRIES ]; then
    echo "❌ Error: PostgreSQL failed to become ready in time."
    exit 1
fi
echo "✅ PostgreSQL is ready and healthy!"

# ==============================================================================
# Update / Create .env configuration
# ==============================================================================
ENV_FILE="$SCRIPT_DIR/.env"
echo "⚙️ Configuring .env file..."

if [ ! -f "$ENV_FILE" ]; then
    touch "$ENV_FILE"
fi

# Helper to update or append key=value in .env
update_env_var() {
    local key="$1"
    local value="$2"
    if grep -q "^${key}=" "$ENV_FILE"; then
        # Replace existing key
        sed -i.bak "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
        rm -f "${ENV_FILE}.bak"
    else
        # Append new key
        echo "${key}=${value}" >> "$ENV_FILE"
    fi
}

update_env_var "DATABASE_URL" "$DB_URL"
update_env_var "DIRECT_URL" "$DB_URL"

# Ensure JWT_SECRET_KEY exists
if ! grep -q "^JWT_SECRET_KEY=" "$ENV_FILE"; then
    RANDOM_SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))" 2>/dev/null || echo "default-secret-key-32-chars-long-12345")
    update_env_var "JWT_SECRET_KEY" "$RANDOM_SECRET"
fi

echo "✅ .env updated with local database URLs:"
echo "   DATABASE_URL=$DB_URL"
echo "   DIRECT_URL=$DB_URL"

# ==============================================================================
# Python Virtual Environment & Migrations
# ==============================================================================
echo "🐍 Locating Python environment..."
if [ -d "$SCRIPT_DIR/venv312" ]; then
    VENV_PATH="$SCRIPT_DIR/venv312"
elif [ -d "$SCRIPT_DIR/venv" ]; then
    VENV_PATH="$SCRIPT_DIR/venv"
elif [ -d "$HOME/cad-material-tracker/venv312" ]; then
    VENV_PATH="$HOME/cad-material-tracker/venv312"
else
    VENV_PATH=""
fi

if [ -n "$VENV_PATH" ]; then
    echo "✅ Using virtual environment: $VENV_PATH"
    # shellcheck disable=SC1090
    source "$VENV_PATH/bin/activate"
else
    echo "ℹ️ Using system python: $(which python3)"
fi

# Apply Alembic Migrations
echo "🔄 Running Alembic migrations..."
alembic upgrade head
echo "✅ Migrations applied successfully!"

# Seed default user
echo "🌱 Seeding initial user..."
python add_user.py

# ==============================================================================
# Restart backend service if running via systemd (e.g. on EC2)
# ==============================================================================
if systemctl list-units --full -all | grep -q "cad-tracker.service"; then
    echo "🔄 Restarting cad-tracker service..."
    sudo systemctl restart cad-tracker
    echo "✅ cad-tracker service restarted!"
fi

echo ""
echo "============================================================"
echo "🎉 LOCAL DATABASE SETUP COMPLETE!"
echo "============================================================"
echo "Database:  PostgreSQL 15 (Docker container: $CONTAINER_NAME)"
echo "Host:      $DB_HOST:$DB_PORT"
echo "Database:  $DB_NAME"
echo "User:      $DB_USER"
echo ""
echo "Default User Credentials:"
echo "  Email:    test@absolutebuilders.com"
echo "  Password: absolutebuilders"
echo "============================================================"
