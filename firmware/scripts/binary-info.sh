#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

BINARY=""
for triple in thumbv7em-none-eabi thumbv6m-none-eabi thumbv7m-none-eabi; do
    if [[ -f "$PROJECT_DIR/target/$triple/release/nordicoin" ]]; then
        BINARY="$PROJECT_DIR/target/$triple/release/nordicoin"
        break
    fi
done

if [[ -z "$BINARY" ]]; then
    echo "No binary found. Build first with: cargo build --release"
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

    if (( lma == 0 || lma < 0x10000000 )); then
        TOTAL_FLASH=$((TOTAL_FLASH + size))
        printf "%-18s%s\n" "$name" "$(human $size)"
    elif (( lma >= 0x20000000 )); then
        TOTAL_RAM=$((TOTAL_RAM + size))
        printf "%-18s%s\n" "$name" "$(human $size)"
    else
        TOTAL_FLASH=$((TOTAL_FLASH + size))
        printf "%-18s%s\n" "$name" "$(human $size)"
    fi
done < <(llvm-objdump -h "$BINARY" 2>/dev/null | grep -E '^\s+[0-9]+')

echo ""
echo "Summary:"
printf "%-18s%s\n" "FLASH:" "$(human $TOTAL_FLASH)"
printf "%-18s%s\n" "RAM:" "$(human $TOTAL_RAM)"
echo ""
