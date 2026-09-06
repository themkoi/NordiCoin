#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PROFILE="${1:-release}"
BINARY="$PROJECT_DIR/target/thumbv7em-none-eabi/$PROFILE/nordicoin"

if [[ ! -f "$BINARY" ]]; then
    echo "Binary not found at $BINARY"
    exit 1
fi

human() {
    local bytes=$1
    if (( bytes >= 1024 )); then
        echo "$(( bytes / 1024 ))K"
    else
        echo "${bytes}B"
    fi
}

echo "Sections:"

TOTAL_FLASH=0
TOTAL_RAM=0

FLASH_ONLY=0
RAM_ONLY=0
BOTH=0
NEITHER=0

while IFS= read -r line; do
    idx=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | awk '{print $2}')
    size_hex=$(echo "$line" | awk '{print $3}')

    [[ -z "$name" ]] && continue
    [[ "$name" == "Name" ]] && continue
    [[ "$name" =~ ^Idx ]] && continue
    [[ "$idx" =~ ^[0-9]+$ ]] || continue

    [[ "$name" =~ ^\.debug_ ]] && continue
    [[ "$name" == .symtab ]] && continue
    [[ "$name" == .strtab ]] && continue
    [[ "$name" == .shstrtab ]] && continue
    [[ "$name" == .comment ]] && continue
    [[ "$name" == .ARM.attributes ]] && continue
    [[ "$name" == .gnu.sgstubs ]] && continue

    size=$((16#${size_hex}))
    [[ "$size" -eq 0 ]] && continue

    lma_hex=$(echo "$line" | awk '{print $5}')
    lma=$((16#${lma_hex}))

    # Determine category by name
    # Flash-only: .vector_table, .text, .rodata
    # Flash+RAM: .data (initialized)
    # RAM-only: .bss, .uninit (zero-initialized / reserved)
    # Neither: .defmt (host-side metadata)
    case "$name" in
        .vector_table|.text|.rodata)
            FLASH_ONLY=$((FLASH_ONLY + size))
            printf "%-18s%s  (flash)\n" "$name" "$(human $size)"
            ;;
        .data)
            BOTH=$((BOTH + size))
            printf "%-18s%s  (flash+ram)\n" "$name" "$(human $size)"
            ;;
        .bss|.uninit)
            RAM_ONLY=$((RAM_ONLY + size))
            printf "%-18s%s  (ram)\n" "$name" "$(human $size)"
            ;;
        .defmt)
            NEITHER=$((NEITHER + size))
            printf "%-18s%s  (neither)\n" "$name" "$(human $size)"
            ;;
        *)
            # Fallback: detect by LMA when section name is unknown
            if (( lma >= 0x10000000 )); then
                RAM_ONLY=$((RAM_ONLY + size))
                printf "%-18s%s  (ram, fallback: LMA=0x%x)\n" "$name" "$(human $size)" "$lma"
            elif (( lma > 0 )); then
                FLASH_ONLY=$((FLASH_ONLY + size))
                printf "%-18s%s  (flash, fallback: LMA=0x%x)\n" "$name" "$(human $size)" "$lma"
            else
                NEITHER=$((NEITHER + size))
                printf "%-18s%s  (neither, fallback: LMA=0x%x)\n" "$name" "$(human $size)" "$lma"
            fi
            ;;
    esac

done < <(llvm-objdump -h "$BINARY" 2>/dev/null | grep -E '^\s+[0-9]+')

TOTAL_FLASH=$((FLASH_ONLY + BOTH))
TOTAL_RAM=$((RAM_ONLY + BOTH))

echo ""
echo "Summary:"
printf "%-18s%s\n" "FLASH:" "$(human $TOTAL_FLASH)"
printf "%-18s%s\n" "RAM:"  "$(human $TOTAL_RAM)"
echo ""
