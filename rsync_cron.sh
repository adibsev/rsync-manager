#!/bin/bash

# Pastikan script menggunakan PATH yang lengkap
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Dapatkan path absolut dari direktori tempat script ini berada
# Ini wajib untuk Cron agar tidak salah membaca file config dan log
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
CONFIG="$DIR/rsync_manager.conf"
LOGFILE="$DIR/rsync_manager.log"

# Hentikan eksekusi jika file konfigurasi belum dibuat
if [ ! -f "$CONFIG" ]; then
    exit 0
fi

# Fungsi log khusus Cron (ditandai dengan tag [CRON])
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CRON] $1" >> "$LOGFILE"
}

# Cek dependensi secara diam-diam
command -v rsync >/dev/null 2>&1 || { log "ERROR: rsync belum terinstall"; exit 1; }

########################################
# FUNGSI PEMBANTU
########################################

list_sync() {
    awk '
    /^\[SYNC\]/ { flag=1; next }
    /^\[/ { flag=0 }
    flag && NF && $0 !~ /^#/ { print }
    ' "$CONFIG"
}

is_local_path() {
    local path="$1"
    if [[ "$path" =~ ^[^/@]+@[^/:]+: ]]; then return 1; fi
    return 0
}

fix_local_owner() {
    local path="$1"
    local owner="$2"

    if [ -z "$owner" ]; then return; fi
    if ! is_local_path "$path"; then return; fi
    if [[ "$path" != /* ]]; then return; fi

    chown -R "$owner" "$path" 2>/dev/null
    if [ $? -eq 0 ]; then
        log "LOCAL OWNER FIX $path -> $owner"
    else
        log "LOCAL OWNER FIX FAILED $path -> $owner"
    fi
}

########################################
# RSYNC OPTIONS (Tanpa Verbose/Progress)
########################################
# Dihapus opsi -v (verbose) dan --progress agar cron tidak bising
RSYNC_COPY_OPTIONS=(
    -r                 # Rekursif
    -t                 # Pertahankan waktu modifikasi
    --modify-window=2  # Toleransi waktu 2 detik
    --update           # Update file terbaru saja
    --no-owner
    --no-group
    --no-perms
    -e "ssh -o StrictHostKeyChecking=no" 
)

########################################
# CRON ENGINE
########################################

sync_pair() {
    local src="$1"
    local mode="$2"
    local dst="$3"
    local pass="$4"
    local owner_group="$5"

    local CMD_PREFIX=()
    if [ -n "$pass" ]; then
        CMD_PREFIX=(sshpass -p "$pass")
    fi

    # Buat direktori lokal jika belum ada
    if is_local_path "$dst"; then
        mkdir -p "$dst" 2>/dev/null
        if [ $? -ne 0 ]; then
            log "ERROR: mkdir gagal untuk $dst"
            return 1
        fi
    fi

    case "$mode" in
        oneway)
            if "${CMD_PREFIX[@]}" rsync "${RSYNC_COPY_OPTIONS[@]}" -q "$src/" "$dst/"; then
                fix_local_owner "$dst" "$owner_group"
                fix_local_owner "$src" "$owner_group"
                log "SUCCESS ONEWAY: $src -> $dst"
            else
                log "FAILED ONEWAY: $src -> $dst"
            fi
            ;;

        mirror)
            if "${CMD_PREFIX[@]}" rsync "${RSYNC_COPY_OPTIONS[@]}" --delete -q "$src/" "$dst/"; then
                fix_local_owner "$dst" "$owner_group"
                fix_local_owner "$src" "$owner_group"
                log "SUCCESS MIRROR: $src -> $dst"
            else
                log "FAILED MIRROR: $src -> $dst"
            fi
            ;;

        twoway)
            # Step 1: Src -> Dst
            if ! "${CMD_PREFIX[@]}" rsync "${RSYNC_COPY_OPTIONS[@]}" -q "$src/" "$dst/"; then
                log "FAILED TWOWAY (Step 1): $src -> $dst"
                return 1
            fi

            # Step 2: Dst -> Src
            if ! "${CMD_PREFIX[@]}" rsync "${RSYNC_COPY_OPTIONS[@]}" -q "$dst/" "$src/"; then
                log "FAILED TWOWAY (Step 2): $dst -> $src"
                return 1
            fi

            fix_local_owner "$dst" "$owner_group"
            fix_local_owner "$src" "$owner_group"
            log "SUCCESS TWOWAY: $src <-> $dst"
            ;;
    esac
}

########################################
# EXECUTE ALL
########################################

mapfile -t lines < <(list_sync)

if [ ${#lines[@]} -gt 0 ]; then
    log "STARTING CRON SYNC"
    for line in "${lines[@]}"; do
        [ -z "$line" ] && continue

        src=$(echo "$line" | cut -d'|' -f1)
        mode=$(echo "$line" | cut -d'|' -f2)
        dst=$(echo "$line" | cut -d'|' -f3)
        pass=$(echo "$line" | cut -d'|' -f4)
        owner_group=$(echo "$line" | cut -d'|' -f5)

        if [ -n "$src" ] && [ -n "$mode" ] && [ -n "$dst" ]; then
            sync_pair "$src" "$mode" "$dst" "$pass" "$owner_group"
        else
            log "INVALID CONFIG LINE: $line"
        fi
    done
    log "FINISHED CRON SYNC"
fi  