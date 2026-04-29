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
LANGUAGE="${CHATGPT2API_LANG:-zh}"
FINAL_AUTH_KEY=""
KEY_GENERATED="false"
SCRIPT_URL="${CHATGPT2API_INSTALL_SCRIPT_URL:-https://raw.githubusercontent.com/basketikun/chatgpt2api/main/deploy/install.sh}"

log() {
  printf '[%s] %s\n' "$APP_NAME" "$*"
}

die() {
  printf '[%s] ERROR: %s\n' "$APP_NAME" "$*" >&2
  exit 1
}

is_tty_available() {
  [ -r /dev/tty ] && [ -w /dev/tty ]
}

is_interactive() {
  [ "$YES" != "true" ] && is_tty_available
}

clear_screen() {
  if [ -t 1 ] && [ "${CHATGPT2API_NO_CLEAR:-}" = "" ] && command -v clear >/dev/null 2>&1; then
    clear
  fi
}

prompt_tty() {
  local prompt="$1"
  local value
  is_tty_available || die "Interactive input requires a TTY. Re-run with --auth-key or -y."
  printf '%s' "$prompt" >/dev/tty
  if ! IFS= read -r value </dev/tty; then
    die "Failed to read interactive input."
  fi
  printf '%s' "$value"
}

print_banner() {
  cat <<'EOF'
   ____ _           _    ____ ____ _____ ____    _    ____ ___
  / ___| |__   __ _| |_ / ___|  _ \_   _|___ \  / \  |  _ \_ _|
 | |   | '_ \ / _` | __| |  _| |_) || |   __) |/ _ \ | |_) | |
 | |___| | | | (_| | |_| |_| |  __/ | |  / __// ___ \|  __/| |
  \____|_| |_|\__,_|\__|\____|_|    |_| |_____/_/   \_\_|  |___|

ChatGPT2API One-click Installer
EOF
}

msg() {
  case "${LANGUAGE}:${1}" in
    en:key_intro) printf 'Set your access key.\nThis key will be used to authorize API requests.\n\n' ;;
    zh:key_intro) printf '请设置访问 Key。\n该 Key 将用于 API 请求鉴权。\n\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

text() {
  case "${LANGUAGE}:${1}" in
    en:select_prompt) printf 'Select [1/2], default 1: ' ;;
    en:key_prompt) printf 'Enter auth-key, or press Enter to auto-generate:\n> ' ;;
    en:key_generated) printf 'auto-generated auth-key' ;;
    en:key_saved) printf 'auth-key saved to %s' "$2" ;;
    en:keep_config) printf 'Keeping existing config: %s' "$2" ;;
    en:prepare_dir) printf 'Preparing install directory...' ;;
    en:write_compose) printf 'Writing Docker Compose config...' ;;
    en:pull_image) printf 'Pulling image %s...' "$2" ;;
    en:start_image) printf 'Starting service...' ;;
    en:build_local) printf 'Building and starting from local source...' ;;
    en:clone_source) printf 'Cloning %s (%s)...' "$2" "$3" ;;
    en:update_source) printf 'Updating source at %s...' "$2" ;;
    en:done) printf 'Deployment completed.' ;;
    en:url_label) printf 'URL:' ;;
    en:request_label) printf 'Use it in requests as:' ;;
    en:commands_label) printf 'Useful commands:' ;;
    en:status_cmd) printf 'Status:  cd %s && docker compose ps' "$2" ;;
    en:logs_cmd) printf 'Logs:    cd %s && docker compose logs -f app' "$2" ;;
    en:upgrade_cmd) printf 'Upgrade: curl -fsSL %s | sudo bash -s -- upgrade' "$2" ;;
    en:cleanup_cmd) printf 'Cleanup: curl -fsSL %s | sudo bash -s -- cleanup' "$2" ;;
    zh:select_prompt) printf '请选择 [1/2]，默认 1: ' ;;
    zh:key_prompt) printf '请输入 auth-key，直接回车将自动生成:\n> ' ;;
    zh:key_generated) printf '已自动生成 auth-key' ;;
    zh:key_saved) printf 'auth-key 已写入 %s' "$2" ;;
    zh:keep_config) printf '保留已有配置: %s' "$2" ;;
    zh:prepare_dir) printf '正在准备部署目录...' ;;
    zh:write_compose) printf '正在写入 Docker Compose 配置...' ;;
    zh:pull_image) printf '正在拉取镜像 %s...' "$2" ;;
    zh:start_image) printf '正在启动服务...' ;;
    zh:build_local) printf '正在从源码构建并启动服务...' ;;
    zh:clone_source) printf '正在克隆 %s (%s)...' "$2" "$3" ;;
    zh:update_source) printf '正在更新源码目录 %s...' "$2" ;;
    zh:done) printf '部署完成。' ;;
    zh:url_label) printf '访问地址:' ;;
    zh:request_label) printf '请求时使用:' ;;
    zh:commands_label) printf '常用命令:' ;;
    zh:status_cmd) printf '查看状态: cd %s && docker compose ps' "$2" ;;
    zh:logs_cmd) printf '查看日志: cd %s && docker compose logs -f app' "$2" ;;
    zh:upgrade_cmd) printf '升级服务: curl -fsSL %s | sudo bash -s -- upgrade' "$2" ;;
    zh:cleanup_cmd) printf '清理服务: curl -fsSL %s | sudo bash -s -- cleanup' "$2" ;;
    *) printf '%s' "$1" ;;
  esac
}

select_language() {
  case "$LANGUAGE" in
    en|EN|english|English) LANGUAGE="en" ;;
    *) LANGUAGE="zh" ;;
  esac

  if ! is_interactive; then
    return 0
  fi

  clear_screen
  print_banner
  cat <<'EOF'

请选择语言 / Select language:
  1) 中文
  2) English

EOF
  local choice
  choice="$(prompt_tty "$(text select_prompt)")"
  case "$choice" in
    2) LANGUAGE="en" ;;
    *) LANGUAGE="zh" ;;
  esac
  printf '\n'
}

prepare_auth_key_prompt() {
  if [ -f "${INSTALL_DIR}/config.json" ] || [ -n "$AUTH_KEY" ] || ! is_interactive; then
    return 0
  fi
  msg key_intro
  AUTH_KEY="$(prompt_tty "$(text key_prompt)")"
  printf '\n'
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
  is_tty_available || die "Confirmation requires a TTY. Re-run with -y to skip prompts."
  printf '%s [y/N] ' "$1" >/dev/tty
  answer="$(prompt_tty "")"
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
  log "$(text prepare_dir)"
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

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

read_config_auth_key() {
  local config_path="$1"
  [ -f "$config_path" ] || return 0
  sed -n 's/^[[:space:]]*"auth-key"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$config_path" | head -n 1
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
    FINAL_AUTH_KEY="$(read_config_auth_key "$config_path")"
    log "$(text keep_config "$config_path")"
    return 0
  fi

  local key
  key="$(generate_auth_key)"
  if [ -z "$AUTH_KEY" ]; then
    KEY_GENERATED="true"
  fi
  FINAL_AUTH_KEY="$key"
  local escaped_key
  escaped_key="$(json_escape "$key")"
  cat >"$config_path" <<EOF
{
  "auth-key": "${escaped_key}",
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
  if [ "$KEY_GENERATED" = "true" ]; then
    log "$(text key_generated)"
  fi
  log "$(text key_saved "$config_path")"
}

write_image_compose() {
  log "$(text write_compose)"
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
    log "$(text clone_source "$REPO_URL" "$REPO_BRANCH")"
    git clone --branch "$REPO_BRANCH" "$REPO_URL" "$source_dir"
    return 0
  fi

  log "$(text update_source "$source_dir")"
  git -C "$source_dir" fetch --all --tags
  git -C "$source_dir" checkout "$REPO_BRANCH"
  git -C "$source_dir" pull --ff-only
}

write_local_compose() {
  log "$(text write_compose)"
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

print_success() {
  printf '\n%s\n\n' "$(text done)"
  printf '%s\n  http://127.0.0.1:%s\n\n' "$(text url_label)" "$APP_PORT"

  if [ -n "$FINAL_AUTH_KEY" ]; then
    printf 'API Key:\n  %s\n\n' "$FINAL_AUTH_KEY"
    printf '%s\n  Authorization: Bearer %s\n\n' "$(text request_label)" "$FINAL_AUTH_KEY"
  fi

  printf '%s\n' "$(text commands_label)"
  printf '  %s\n' "$(text status_cmd "$INSTALL_DIR")"
  printf '  %s\n' "$(text logs_cmd "$INSTALL_DIR")"
  printf '  %s\n' "$(text upgrade_cmd "$SCRIPT_URL")"
  printf '  %s\n' "$(text cleanup_cmd "$SCRIPT_URL")"
}

install_or_upgrade() {
  require_common_commands
  ensure_install_dir
  write_env_file
  write_config_if_missing

  if [ "$MODE" = "local" ]; then
    sync_source
    write_local_compose
    log "$(text build_local)"
    (cd "$INSTALL_DIR" && compose up -d --build)
  else
    write_image_compose
    log "$(text pull_image "$IMAGE")"
    (cd "$INSTALL_DIR" && compose pull)
    log "$(text start_image)"
    (cd "$INSTALL_DIR" && compose up -d)
  fi

  print_success
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

  case "$COMMAND" in
    install|upgrade)
      select_language
      ;;
  esac

  validate_args

  case "$COMMAND" in
    install|upgrade)
      prepare_auth_key_prompt
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
