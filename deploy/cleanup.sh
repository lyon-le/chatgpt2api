#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="chatgpt2api"
DEFAULT_INSTALL_DIR="/opt/${APP_NAME}"
DEFAULT_IMAGE="ghcr.io/basketikun/chatgpt2api:latest"

INSTALL_DIR="${CHATGPT2API_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
IMAGE="${CHATGPT2API_IMAGE:-$DEFAULT_IMAGE}"
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
  cleanup.sh [options]

Options:
  --dir PATH        Install directory (default: ${DEFAULT_INSTALL_DIR})
  --image-name IMG  Published image to remove with --remove-images
  --purge           Delete install directory, including config and data
  --remove-images   Remove related Docker images
  -y, --yes         Do not prompt for confirmation
  -h, --help        Show this help

Examples:
  bash cleanup.sh
  bash cleanup.sh --purge --remove-images
EOF
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      cleanup|uninstall)
        shift
        ;;
      --dir)
        [ "$#" -ge 2 ] || die "--dir requires a path"
        INSTALL_DIR="$2"
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
      -h|--help|help)
        usage
        exit 0
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

parse_args "$@"
validate_args
cleanup
