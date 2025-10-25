#!/usr/bin/env sh

version_lt() {
    if [ "$1" = "$2" ]; then
        return 1
    fi
    printf '%s\n%s' "$1" "$2" | sort -C -V
}

get_file() {
    curl --location --remote-name --no-progress-meter --fail "$1" || {
        echo "Failed to download $1" 1>&2
        exit 1
    }
}

verify_file () {
    local FILE="$1"
    local PUBKEY="$2"
    minisign -Vm "${FILE}" -P "${PUBKEY}" || {
        echo "Failed to verify ${FILE}" 1>&2
        exit 1
    }
}

get_zig_mirror() {
    local ZIG_MIRROR="$1"
    local ZIG_TARBALL_NAME="$2"

    local ZIG_URL="${ZIG_MIRROR}/${ZIG_TARBALL_NAME}.tar.xz?source=devcontainers-zig-template"
    local ZIG_SIGNATURE_URL="${ZIG_MIRROR}/${ZIG_TARBALL_NAME}.tar.xz.minisig?source=devcontainers-zig-template"
    local ZIG_PUBKEY="RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U"

    curl --location --remote-name --no-progress-meter --fail "$ZIG_URL" && \
    curl --location --remote-name --no-progress-meter --fail "$ZIG_SIGNATURE_URL" && \
    minisign -Vm "${ZIG_TARBALL_NAME}.tar.xz" -P "${ZIG_PUBKEY}"
}

get_zig_tarball() {
    local ZIG_VERSION="$1"

    # Tarball naming changed after Zig 0.14.1
    if version_lt "${ZIG_VERSION}" "0.14.1"; then
        local ZIG_TARBALL_NAME="zig-linux-x86_64-${ZIG_VERSION}"
    else
        local ZIG_TARBALL_NAME="zig-x86_64-linux-${ZIG_VERSION}"
    fi

    # Get community mirror list
    get_file "https://ziglang.org/download/community-mirrors.txt"

    # Randomize the mirror list
    local tmpfile=$(mktemp "${file}.XXXXXX") || exit 1
    awk 'BEGIN { srand() } { printf "%f\t%s\n", rand(), $0 }' "community-mirrors.txt" | sort -k1,1n | cut -f2- > "${tmpfile}"
    mv "${tmpfile}" "community-mirrors.txt"

    while IFS= read -r URL; do
        get_zig_mirror "${URL}" "${ZIG_TARBALL_NAME}"
        if [ $? -eq 0 ]; then
            tar -xf "${ZIG_TARBALL_NAME}.tar.xz"
            ln -s "/home/vscode/${ZIG_TARBALL_NAME}/zig" /home/vscode/.local/bin/zig
            return 0
        else
            echo "Failed to download zig from community mirror: ${URL}" 1>&2
        fi
    done < "community-mirrors.txt"

    echo "All community mirrors failed. Falling back to official server" 1>&2
    get_zig_mirror "https://ziglang.org/download/${ZIG_VERSION}" "${ZIG_TARBALL_NAME}" || {
        echo "Failed to download zig from all mirrors and official server" 1>&2
        exit 1
    }

    tar -xf "${ZIG_TARBALL_NAME}.tar.xz"
    ln -s "/home/vscode/${ZIG_TARBALL_NAME}/zig" /home/vscode/.local/bin/zig
    return 0
}

MINISIGN_VERSION="$2"
MINISIGN_URL="https://github.com/jedisct1/minisign/releases/download/${MINISIGN_VERSION}/minisign-${MINISIGN_VERSION}-linux.tar.gz"
MINISIGN_SIGNATURE_URL="https://github.com/jedisct1/minisign/releases/download/${MINISIGN_VERSION}/minisign-${MINISIGN_VERSION}-linux.tar.gz.minisig"
MINISIGN_PUBKEY="RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3"

ZIG_VERSION="$1"
ZLS_VERSION="$(echo "${ZIG_VERSION}" | cut -d. -f1,2).0"

# ZLS Tarball naming changed after ZLS 0.15.0
if version_lt "${ZLS_VERSION}" "0.15.0"; then
    ZLS_TARBALL_NAME="zls-linux-x86_64-${ZLS_VERSION}"
else
    ZLS_TARBALL_NAME="zls-x86_64-linux-${ZLS_VERSION}"
fi

ZLS_URL="https://builds.zigtools.org/${ZLS_TARBALL_NAME}.tar.xz"
ZLS_SIGNATURE_URL="https://builds.zigtools.org/${ZLS_TARBALL_NAME}.tar.xz.minisig"
ZLS_PUBKEY="RWR+9B91GBZ0zOjh6Lr17+zKf5BoSuFvrx2xSeDE57uIYvnKBGmMjOex"

mkdir -p "/home/vscode/.local/bin"

get_file "${MINISIGN_URL}"
tar -xzf "minisign-${MINISIGN_VERSION}-linux.tar.gz"
ln -s /home/vscode/minisign-linux/x86_64/minisign /home/vscode/.local/bin/minisign

get_file "${MINISIGN_SIGNATURE_URL}"
verify_file minisign-"${MINISIGN_VERSION}"-linux.tar.gz ${MINISIGN_PUBKEY}

get_zig_tarball "${ZIG_VERSION}"

get_file "${ZLS_URL}"
get_file "${ZLS_SIGNATURE_URL}"
verify_file "${ZLS_TARBALL_NAME}.tar.xz" "${ZLS_PUBKEY}"

tar -xf "${ZLS_TARBALL_NAME}.tar.xz"
ln -s "/home/vscode/zls" /home/vscode/.local/bin/zls
