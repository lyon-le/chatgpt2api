#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="chatgpt2api"
DEFAULT_INSTALL_DIR="/opt/${APP_NAME}"
DEFAULT_REPO_URL="https://github.com/basketikun/chatgpt2api.git"
DEFAULT_REPO_BRANCH="main"
DEFAULT_IMAGE="ghcr.io/basketikun/chatgpt2api:latest"
DEFAULT_PORT="3000"

COMMAND="install"
MODE="image"
INSTALL_DIR="${CHATGPT2API_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
REPO_URL="${CHATGPT2API_REPO_URL:-$DEFAULT_REPO_URL}"
REPO_BRANCH="${CHATGPT2API_REPO_BRANCH:-$DEFAULT_REPO_BRANCH}"
IMAGE="${CHATGPT2API_IMAGE:-$DEFAULT_IMAGE}"
APP_PORT="${CHATGPT2API_PORT:-$DEFAULT_PORT}"
AUTH_KEY="${CHATGPT2API_AUTH_KEY:-}"
PURGE="false"
REMOVE_IMAGES="false"
YES="false"

log() {
  printf '[%s] %s\n' "$APP_NAME" "$*"
}

die() {
  printf '[%s] ERROR: %s\n' "$APP_NAME" "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  install.sh [command] [options]

Commands:
  install       Install and start ${APP_NAME} (default)
  upgrade       Update image/source and restart
  uninstall     Stop and remove containers, keep data by default
  cleanup       Alias of uninstall
  status        Show docker compose status
  logs          Follow app logs
  help          Show this help

Options:
  --local              Build from source with Dockerfile
  --image              Use published image (default)
  --dir PATH           Install directory (default: ${DEFAULT_INSTALL_DIR})
  --port PORT          Host port mapped to container port 80 (default: ${DEFAULT_PORT})
  --auth-key KEY       Auth key written to config.json on first install
  --repo URL           Git repository for --local mode
  --branch BRANCH      Git branch for --local mode (default: ${DEFAULT_REPO_BRANCH})
  --image-name IMAGE   Image for --image mode (default: ${DEFAULT_IMAGE})
  --purge              With uninstall/cleanup, also delete install directory and data
  --remove-images      With uninstall/cleanup, remove related Docker images
  -y, --yes            Do not prompt for confirmation
  -h, --help           Show this help

Examples:
  bash install.sh install
  bash install.sh install --local
  bash install.sh upgrade
  bash install.sh upgrade --local
  bash install.sh cleanup
  bash install.sh cleanup --purge --remove-images
EOF
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      install|upgrade|uninstall|cleanup|status|logs|help)
        COMMAND="$1"
        shift
        ;;
      --local|--build)
        MODE="local"
        shift
        ;;
      --image)
        MODE="image"
        shift
        ;;
      --dir)
        [ "$#" -ge 2 ] || die "--dir requires a path"
        INSTALL_DIR="$2"
        shift 2
        ;;
      --port)
        [ "$#" -ge 2 ] || die "--port requires a value"
        APP_PORT="$2"
        shift 2
        ;;
      --auth-key)
        [ "$#" -ge 2 ] || die "--auth-key requires a value"
        AUTH_KEY="$2"
        shift 2
        ;;
      --repo)
        [ "$#" -ge 2 ] || die "--repo requires a URL"
        REPO_URL="$2"
        shift 2
        ;;
      --branch)
        [ "$#" -ge 2 ] || die "--branch requires a branch name"
        REPO_BRANCH="$2"
        shift 2
        ;;
      --image-name)
        [ "$#" -ge 2 ] || die "--image-name requires an image reference"
        IMAGE="$2"
        shift 2
        ;;
      --purge)
        PURGE="true"
        shift
        ;;
      --remove-images)
        REMOVE_IMAGES="true"
        shift
        ;;
      -y|--yes)
        YES="true"
        shift
        ;;
      -h|--help)
        COMMAND="help"
        shift
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

have_sudo() {
  command -v sudo >/dev/null 2>&1
}

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
    return $?
  fi
  if "$@" 2>/dev/null; then
    return 0
  fi
  if have_sudo; then
    sudo "$@"
  else
    die "This action needs root permission. Run as root or install sudo."
  fi
}

compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    die "Docker Compose is not available. Install Docker Compose v2 or docker-compose."
  fi
}

require_common_commands() {
  command -v docker >/dev/null 2>&1 || die "Docker is not installed or not in PATH."
  docker info >/dev/null 2>&1 || die "Docker daemon is not reachable."
  compose version >/dev/null
}

require_local_commands() {
  command -v git >/dev/null 2>&1 || die "git is required for --local mode."
}

confirm() {
  if [ "$YES" = "true" ]; then
    return 0
  fi
  printf '%s [y/N] ' "$1"
  if ! read -r answer; then
    die "Confirmation required. Re-run with -y to skip prompts."
  fi
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) die "Cancelled." ;;
  esac
}

validate_args() {
  [ -n "$INSTALL_DIR" ] || die "--dir cannot be empty"
  [ "$INSTALL_DIR" != "/" ] || die "--dir cannot be /"
  case "$APP_PORT" in
    ''|*[!0-9]*) die "--port must be a number" ;;
  esac
}

ensure_install_dir() {
  as_root mkdir -p "$INSTALL_DIR/data"
  if [ "$(id -u)" -ne 0 ]; then
    as_root chown -R "$(id -u):$(id -g)" "$INSTALL_DIR"
  fi
}

generate_auth_key() {
  if [ -n "$AUTH_KEY" ]; then
    printf '%s' "$AUTH_KEY"
  elif command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24
  elif [ -r /proc/sys/kernel/random/uuid ]; then
    tr -d '-' </proc/sys/kernel/random/uuid
  else
    date +%s%N
  fi
}

write_env_file() {
  cat >"${INSTALL_DIR}/.env" <<EOF
APP_PORT=${APP_PORT}
CHATGPT2API_IMAGE=${IMAGE}
STORAGE_BACKEND=${STORAGE_BACKEND:-}
DATABASE_URL=${DATABASE_URL:-}
GIT_REPO_URL=${GIT_REPO_URL:-}
GIT_TOKEN=${GIT_TOKEN:-}
GIT_BRANCH=${GIT_BRANCH:-}
GIT_FILE_PATH=${GIT_FILE_PATH:-}
CHATGPT2API_BASE_URL=${CHATGPT2API_BASE_URL:-}
EOF
}

write_config_if_missing() {
  local config_path="${INSTALL_DIR}/config.json"
  if [ -f "$config_path" ]; then
    log "Keeping existing config: ${config_path}"
    return 0
  fi

  local key
  key="$(generate_auth_key)"
  cat >"$config_path" <<EOF
{
  "auth-key": "${key}",
  "refresh_account_interval_minute": 60,
  "image_retention_days": 15,
  "auto_remove_rate_limited_accounts": false,
  "auto_remove_invalid_accounts": true,
  "log_levels": [
    "debug",
    "error",
    "info",
    "warning"
  ],
  "proxy": "",
  "base_url": ""
}
EOF
  chmod 600 "$config_path"
  log "Created config.json with auth-key: ${key}"
}

write_image_compose() {
  cat >"${INSTALL_DIR}/docker-compose.yml" <<'EOF'
services:
  app:
    image: ${CHATGPT2API_IMAGE}
    container_name: chatgpt2api
    restart: unless-stopped
    ports:
      - "${APP_PORT}:80"
    volumes:
      - ./data:/app/data
      - ./config.json:/app/config.json
    environment:
      STORAGE_BACKEND: ${STORAGE_BACKEND:-json}
      DATABASE_URL: ${DATABASE_URL:-}
      GIT_REPO_URL: ${GIT_REPO_URL:-}
      GIT_TOKEN: ${GIT_TOKEN:-}
      GIT_BRANCH: ${GIT_BRANCH:-main}
      GIT_FILE_PATH: ${GIT_FILE_PATH:-accounts.json}
      CHATGPT2API_BASE_URL: ${CHATGPT2API_BASE_URL:-}
EOF
  printf '%s\n' "image" >"${INSTALL_DIR}/.deploy-mode"
}

sync_source() {
  require_local_commands
  local source_dir="${INSTALL_DIR}/source"

  if [ ! -d "${source_dir}/.git" ]; then
    if [ -e "$source_dir" ]; then
      die "${source_dir} exists but is not a git repository."
    fi
    log "Cloning ${REPO_URL} (${REPO_BRANCH})..."
    git clone --branch "$REPO_BRANCH" "$REPO_URL" "$source_dir"
    return 0
  fi

  log "Updating source at ${source_dir}..."
  git -C "$source_dir" fetch --all --tags
  git -C "$source_dir" checkout "$REPO_BRANCH"
  git -C "$source_dir" pull --ff-only
}

write_local_compose() {
  cat >"${INSTALL_DIR}/docker-compose.yml" <<'EOF'
services:
  app:
    build:
      context: ./source
      dockerfile: Dockerfile
    image: chatgpt2api:local
    container_name: chatgpt2api-local
    restart: unless-stopped
    ports:
      - "${APP_PORT}:80"
    volumes:
      - ./data:/app/data
      - ./config.json:/app/config.json
    environment:
      STORAGE_BACKEND: ${STORAGE_BACKEND:-sqlite}
      DATABASE_URL: ${DATABASE_URL:-sqlite:////app/data/accounts.db}
      GIT_REPO_URL: ${GIT_REPO_URL:-}
      GIT_TOKEN: ${GIT_TOKEN:-}
      GIT_BRANCH: ${GIT_BRANCH:-main}
      GIT_FILE_PATH: ${GIT_FILE_PATH:-accounts.json}
      CHATGPT2API_BASE_URL: ${CHATGPT2API_BASE_URL:-}
EOF
  printf '%s\n' "local" >"${INSTALL_DIR}/.deploy-mode"
}

install_or_upgrade() {
  require_common_commands
  ensure_install_dir
  write_env_file
  write_config_if_missing

  if [ "$MODE" = "local" ]; then
    sync_source
    write_local_compose
    log "Building and starting from local source..."
    (cd "$INSTALL_DIR" && compose up -d --build)
  else
    write_image_compose
    log "Pulling image ${IMAGE}..."
    (cd "$INSTALL_DIR" && compose pull)
    log "Starting from published image..."
    (cd "$INSTALL_DIR" && compose up -d)
  fi

  log "Done. Open: http://127.0.0.1:${APP_PORT}"
  log "Install dir: ${INSTALL_DIR}"
}

show_status() {
  require_common_commands
  [ -f "${INSTALL_DIR}/docker-compose.yml" ] || die "No compose file found in ${INSTALL_DIR}."
  (cd "$INSTALL_DIR" && compose ps)
}

show_logs() {
  require_common_commands
  [ -f "${INSTALL_DIR}/docker-compose.yml" ] || die "No compose file found in ${INSTALL_DIR}."
  (cd "$INSTALL_DIR" && compose logs -f app)
}

remove_images() {
  docker image rm "$IMAGE" >/dev/null 2>&1 || true
  docker image rm "chatgpt2api:local" >/dev/null 2>&1 || true
}

cleanup() {
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 && [ -f "${INSTALL_DIR}/docker-compose.yml" ]; then
    log "Stopping containers..."
    (cd "$INSTALL_DIR" && compose down --remove-orphans)
  elif [ -f "${INSTALL_DIR}/docker-compose.yml" ]; then
    log "Docker is not reachable; skipping compose down."
  else
    log "No compose file found in ${INSTALL_DIR}; skipping compose down."
  fi

  if [ "$REMOVE_IMAGES" = "true" ]; then
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
      log "Removing Docker images..."
      remove_images
    else
      log "Docker is not reachable; skipping image removal."
    fi
  fi

  if [ "$PURGE" = "true" ]; then
    confirm "This will delete ${INSTALL_DIR}, including config and data. Continue?"
    as_root rm -rf "$INSTALL_DIR"
    log "Deleted ${INSTALL_DIR}"
  else
    log "Data kept in ${INSTALL_DIR}. Use --purge to delete it."
  fi
}

main() {
  parse_args "$@"

  if [ "$COMMAND" = "help" ]; then
    usage
    exit 0
  fi

  validate_args

  case "$COMMAND" in
    install|upgrade)
      install_or_upgrade
      ;;
    uninstall|cleanup)
      cleanup
      ;;
    status)
      show_status
      ;;
    logs)
      show_logs
      ;;
    *)
      die "Unknown command: ${COMMAND}"
      ;;
  esac
}

main "$@"
