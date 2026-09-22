#!/bin/bash

CONFIG="rsync_manager.conf"
LOGFILE="rsync_manager.log"

touch "$CONFIG"
touch "$LOGFILE"

########################################
# INIT
########################################

init_config() {
    if ! grep -q "^\[SYNC\]" "$CONFIG"; then
        cat > "$CONFIG" << EOF
[SYNC]
EOF
    fi
}

cek_rsync() {
    command -v rsync >/dev/null 2>&1 || {
        echo "rsync belum terinstall"
        exit 1
    }
    command -v sshpass >/dev/null 2>&1 || {
        echo "sshpass belum terinstall. Install dengan: apt install sshpass atau yum install sshpass"
        exit 1
    }
}

pause() {
    read -p "ENTER..."
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"
}

########################################
# PARSE CONFIG
########################################

list_sync() {
    awk '
    /^\[SYNC\]/ { flag=1; next }
    /^\[/ { flag=0 }
    flag && NF && $0 !~ /^#/ { print }
    ' "$CONFIG"
}

########################################
# DETECT LOCAL PATH
########################################

is_local_path() {
    local path="$1"
    # Remote SSH (ada format user@host:)
    if [[ "$path" =~ ^[^/@]+@[^/:]+: ]]; then
        return 1
    fi
    return 0
}

########################################
# FIX LOCAL OWNERSHIP
########################################

fix_local_owner() {
    local path="$1"
    local owner="$2"

    # Jika owner tidak diatur, lewati
    if [ -z "$owner" ]; then
        return
    fi

    # Jangan jalankan di path remote
    if ! is_local_path "$path"; then
        return
    fi

    # Hanya proses path absolut lokal
    if [[ "$path" != /* ]]; then
        return
    fi

    echo ""
    echo "Memastikan owner lokal:"
    echo "PATH  : $path"
    echo "OWNER : $owner"

    chown -R "$owner" "$path" 2>/dev/null

    if [ $? -eq 0 ]; then
        log "LOCAL OWNER FIX $path -> $owner"
    else
        echo "WARNING: gagal mengubah owner $path"
        log "LOCAL OWNER FIX FAILED $path -> $owner"
    fi
}

########################################
# RSYNC OPTIONS
########################################

RSYNC_COPY_OPTIONS=(
    -rvh
    -t                 # [BARU] Mempertahankan timestamp asli file
    --modify-window=2  # [BARU] Toleransi perbedaan waktu 2 detik (Wajib untuk PPSSPP/Android/FAT32)
    --update           # Fokus ke file terbaru
    --no-owner         # Abaikan owner dari sumber
    --no-group         # Abaikan grup dari sumber
    --no-perms         # Abaikan permission dari sumber
    -e "ssh -o StrictHostKeyChecking=no" 
)

########################################
# SMART SYNC ENGINE
########################################

sync_pair() {
    local src="$1"
    local mode="$2"
    local dst="$3"
    local pass="$4"
    local owner_group="$5"

    echo ""
    echo "======================================"
    echo "SRC   : $src"
    echo "DST   : $dst"
    echo "MODE  : $mode"
    if [ -n "$owner_group" ]; then
        echo "OWNER : $owner_group (Local)"
    else
        echo "OWNER : Default Sistem"
    fi
    
    if [ -n "$pass" ]; then
        echo "PASS  : Tersimpan (sshpass)"
    else
        echo "PASS  : Tidak Ada / Default SSH Key"
    fi
    echo "======================================"

    local CMD_PREFIX=()
    if [ -n "$pass" ]; then
        CMD_PREFIX=(sshpass -p "$pass")
    fi

    # CREATE LOCAL DESTINATION
    if is_local_path "$dst"; then
        mkdir -p "$dst" 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "ERROR: tidak bisa membuat destination: $dst"
            log "SYNC ERROR mkdir $dst"
            return 1
        fi
    fi

    case "$mode" in
        oneway)
            echo ""
            echo ">>> ONE WAY"
            echo "$src  ->  $dst"
            echo ""

            "${CMD_PREFIX[@]}" rsync \
                "${RSYNC_COPY_OPTIONS[@]}" \
                --progress \
                "$src/" \
                "$dst/"

            if [ $? -eq 0 ]; then
                fix_local_owner "$dst" "$owner_group"
                fix_local_owner "$src" "$owner_group"
                log "ONEWAY $src -> $dst"
            else
                echo "SYNC ERROR"
                log "ONEWAY FAILED $src -> $dst"
            fi
            ;;

        mirror)
            echo ""
            echo ">>> MIRROR"
            echo "$src  ->  $dst"
            echo ""

            "${CMD_PREFIX[@]}" rsync \
                "${RSYNC_COPY_OPTIONS[@]}" \
                --delete \
                --progress \
                "$src/" \
                "$dst/"

            if [ $? -eq 0 ]; then
                fix_local_owner "$dst" "$owner_group"
                fix_local_owner "$src" "$owner_group"
                log "MIRROR $src -> $dst"
            else
                echo "MIRROR ERROR"
                log "MIRROR FAILED $src -> $dst"
            fi
            ;;

        twoway)
            echo ""
            echo ">>> TWO WAY SYNC"
            echo "STEP 1: $src -> $dst"

            "${CMD_PREFIX[@]}" rsync \
                "${RSYNC_COPY_OPTIONS[@]}" \
                --progress \
                "$src/" \
                "$dst/"

            if [ $? -ne 0 ]; then
                echo "ERROR: SRC -> DST gagal"
                log "TWOWAY FAILED SRC->DST $src -> $dst"
                return 1
            fi

            echo ""
            echo "STEP 2: $dst -> $src"

            "${CMD_PREFIX[@]}" rsync \
                "${RSYNC_COPY_OPTIONS[@]}" \
                --progress \
                "$dst/" \
                "$src/"

            if [ $? -ne 0 ]; then
                echo "ERROR: DST -> SRC gagal"
                log "TWOWAY FAILED DST->SRC $dst -> $src"
                return 1
            fi

            # Terapkan owner ke kedua sisi (fungsi akan otomatis skip path remote)
            fix_local_owner "$dst" "$owner_group"
            fix_local_owner "$src" "$owner_group"
            
            log "TWOWAY $src <-> $dst"
            ;;

        *)
            echo "Mode tidak dikenal: $mode"
            log "UNKNOWN MODE $mode"
            return 1
            ;;
    esac
}

########################################
# SYNC ALL
########################################

sync_all() {
    mapfile -t lines < <(list_sync)

    if [ ${#lines[@]} -eq 0 ]; then
        echo "No sync config"
        pause
        return
    fi

    echo ""
    echo "======================================"
    echo "         START SYNC ALL"
    echo "======================================"

    for line in "${lines[@]}"; do
        [ -z "$line" ] && continue

        src=$(echo "$line" | cut -d'|' -f1)
        mode=$(echo "$line" | cut -d'|' -f2)
        dst=$(echo "$line" | cut -d'|' -f3)
        pass=$(echo "$line" | cut -d'|' -f4)
        owner_group=$(echo "$line" | cut -d'|' -f5)

        if [ -z "$src" ] || [ -z "$mode" ] || [ -z "$dst" ]; then
            echo "Config invalid: $line"
            log "CONFIG INVALID $line"
            continue
        fi

        sync_pair "$src" "$mode" "$dst" "$pass" "$owner_group"
    done

    echo ""
    echo "======================================"
    echo "             SYNC DONE"
    echo "======================================"
    pause
}

########################################
# ADD SYNC
########################################

add_sync() {
    echo ""
    echo "=== ADD SYNC CONFIG ==="

    read -p "Source folder: " src
    if [ -z "$src" ]; then
        echo "Source kosong"; pause; return
    fi

    echo ""
    echo "Mode:"
    echo "1. oneway"
    echo "2. twoway"
    echo "3. mirror"
    read -p "Choose mode: " m

    case $m in
        1) mode="oneway" ;;
        2) mode="twoway" ;;
        3) mode="mirror" ;;
        *) echo "invalid"; pause; return ;;
    esac

    echo ""
    read -p "Destination (local or user@ip:/path): " dst
    if [ -z "$dst" ]; then
        echo "Destination kosong"; pause; return
    fi
    
    echo ""
    read -p "SSH Password (kosongkan jika local/pakai SSH Key): " pass

    echo ""
    read -p "Set Owner & Group Lokal (cth: wepey:wepey) [Kosongkan jika default]: " owner_group

    if [[ "$src" == *"|"* ]] || [[ "$dst" == *"|"* ]] || [[ "$pass" == *"|"* ]] || [[ "$owner_group" == *"|"* ]]; then
        echo "ERROR: Input tidak boleh mengandung karakter |"
        pause
        return
    fi

    awk -v line="$src|$mode|$dst|$pass|$owner_group" '
    /^\[SYNC\]/ {
        print
        print line
        next
    }
    { print }
    ' "$CONFIG" > "$CONFIG.tmp"

    mv "$CONFIG.tmp" "$CONFIG"

    echo ""
    echo "ADDED: $src -> $dst [$mode]"
    log "CONFIG ADD $src|$mode|$dst"
    pause
}

########################################
# DELETE SYNC
########################################

delete_sync() {
    echo ""
    echo "=== DELETE SYNC CONFIG ==="
    echo ""

    mapfile -t lines < <(list_sync)

    if [ ${#lines[@]} -eq 0 ]; then
        echo "No data"; pause; return
    fi

    for i in "${!lines[@]}"; do
        display_line=$(echo "${lines[$i]}" | cut -d'|' -f1-3)
        echo "$((i+1)). $display_line"
    done

    echo ""
    read -p "Choose number to delete: " n

    if ! [[ "$n" =~ ^[0-9]+$ ]] || [ "$n" -lt 1 ] || [ "$n" -gt "${#lines[@]}" ]; then
        echo "Nomor tidak valid"; pause; return
    fi

    target="${lines[$((n-1))]}"
    grep -vF -- "$target" "$CONFIG" > "$CONFIG.tmp"
    mv "$CONFIG.tmp" "$CONFIG"

    echo ""
    echo "DELETED: $(echo "$target" | cut -d'|' -f1-3)"
    log "CONFIG DELETE $(echo "$target" | cut -d'|' -f1-3)"
    pause
}

########################################
# MANAGE CONFIG
########################################

manage_config() {
    while true; do
        clear
        echo "======================="
        echo "   CONFIG MANAGER"
        echo "======================="
        echo "1. Add Sync"
        echo "2. Delete Sync"
        echo "3. List"
        echo "0. Back"
        echo "======================="

        read -p "Choose: " c

        case $c in
            1) add_sync ;;
            2) delete_sync ;;
            3)
                clear
                echo "=== SYNC CONFIG ==="
                echo ""
                list_sync | awk -F'|' '{
                    owner = $5 ? $5 : "Default";
                    print $1 " -> " $3 " [" $2 "] (Owner: " owner ")"
                }'
                echo ""
                pause
                ;;
            0) break ;;
            *) echo "Invalid"; sleep 1 ;;
        esac
    done
}

########################################
# VIEW CONFIG & LOG
########################################

view_config() {
    clear
    echo "=============================="
    echo "          CONFIG"
    echo "=============================="
    echo ""
    cat "$CONFIG"
    echo ""
    pause
}

view_log() {
    clear
    echo "=============================="
    echo "            LOG"
    echo "=============================="
    echo ""
    cat "$LOGFILE"
    echo ""
    pause
}

########################################
# MAIN MENU
########################################

menu() {
    while true; do
        clear
        echo "=============================="
        echo "   SIMPLE RSYNC MANAGER"
        echo "        BY WePey"
        echo "=============================="
        echo "1. Sync Now"
        echo "2. Manage Config"
        echo "3. View Config (with passwords)"
        echo "4. View Log"
        echo "0. Exit"
        echo "=============================="

        read -p "Choose: " p

        case $p in
            1) sync_all ;;
            2) manage_config ;;
            3) view_config ;;
            4) view_log ;;
            0) exit 0 ;;
            *) echo "Invalid"; sleep 1 ;;
        esac
    done
}

cek_rsync
init_config
menu