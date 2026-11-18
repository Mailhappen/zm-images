#!/bin/bash
# Build Zimbra's patched nginx on top of upstream nginx 1.30.7 (fixes CVE-2026-123007,
# -121810, -123633, -113425 which Zimbra's own nginx 1.24.0 still has).
#
# Zimbra's nginx is "vanilla nginx tarball + 23 patches + 5 modules" (Zimbra/packages,
# thirdparty/nginx). The patches target 1.24.0; on 1.30.7 most apply, a few do not.
# This script applies them with zero fuzz (rejects are dropped), then applies
# zimbra-nginx-1.30.7-port.patch, which contains our hand-port of everything that was
# rejected. Nothing of Zimbra's is redistributed here: sources are fetched pinned.
#
# Usage: build-nginx.sh [prepare|build]      (env: W=workdir, OUT=output dir)
#   prepare  fetch + patch only (tree in $W/nginx)       -> used to regenerate the port patch
#   build    prepare + configure + make, binary to $OUT/nginx
set -euo pipefail

NGINX_VER=1.30.7
NGINX_SHA256=2565b5c837050e958f70fb0f73c48e2bca4542ad349fd356f46fb0c72610bc6e
# Zimbra/packages: patches + zmmodules (sso, upstreamzmauth, zmauth, throttle)
ZPKG_URL=https://github.com/Zimbra/packages.git
ZPKG_COMMIT=5683195e1c7be7e454d0ad50ff08df978ea26df7
# nginx-tcp-keepalive module, same commit Zimbra pins (versions.def NGINX_HTTP_KEEPALIVE)
KEEPALIVE_URL=https://github.com/nviennot/nginx-tcp-keepalive.git
KEEPALIVE_COMMIT=19755fc0e22aa7d7ac2198f78b297951d31ea1dc
# Headers only (the image has the runtime libs of zimbra-openssl 3.5.1 / zimbra-cyrus-sasl 2.1.28)
OPENSSL_VER=3.5.1
OPENSSL_SHA256=529043b15cffa5f36077a4d0af83f3de399807181d607441d734196d889b641f
SASL_VER=2.1.28
SASL_SHA256=7ccfc6abd01ed67c1a0924b353e526f1b766b21f42d4562ee635a8ebfc5bb38c

HERE=$(cd "$(dirname "$0")" && pwd)
W=${W:-/usr/src/nginx-build}
OUT=${OUT:-/out}
MODE=${1:-build}

# order of Zimbra's nginx.spec (%patch0..%patch22)
PATCHES="nginx_auto_cc nginx_auto_lib nginx_auto_modules nginx_auto_options nginx_auto_sources nginx_README \
 nginx_src_core nginx_src_event nginx_src_http nginx_src_mail_ngx_mail nginx_src_mail_ngx_mail_auth_http_module \
 nginx_src_mail_ngx_mail_core_module nginx_src_mail_ngx_mail_handler nginx_src_mail_ngx_mail_imap_handler \
 nginx_src_mail_ngx_mail_imap_module_c nginx_src_mail_ngx_mail_imap_module_h nginx_src_mail_ngx_mail_parse \
 nginx_src_mail_ngx_mail_pop3_handler nginx_src_mail_ngx_mail_pop3_module_c nginx_src_mail_ngx_mail_pop3_module_h \
 nginx_src_mail_ngx_mail_proxy_module nginx_src_mail_ngx_mail_smtp_module nginx_docs"

fetch() { # file url sha256
  curl -fsSL -o "$1" "$2" && echo "$3  $1" | sha256sum -c -
}
git_pin() { # dir url commit  (content-addressed: the commit hash is verified)
  rm -rf "$1" && git init -q "$1" && git -C "$1" fetch -q --depth 1 "$2" "$3" && git -C "$1" checkout -q FETCH_HEAD
  [ "$(git -C "$1" rev-parse HEAD)" = "$3" ] || { echo "commit mismatch for $2" >&2; exit 1; }
}

mkdir -p "$W" && cd "$W"
rm -rf nginx
fetch "nginx-$NGINX_VER.tar.gz" "https://nginx.org/download/nginx-$NGINX_VER.tar.gz" "$NGINX_SHA256"
mkdir nginx && tar xzf "nginx-$NGINX_VER.tar.gz" -C nginx --strip-components=1
git_pin zpkg "$ZPKG_URL" "$ZPKG_COMMIT"

# 1) Zimbra's patches, zero fuzz. Hunks that do not apply are rejected and dropped on purpose:
#    - max_headers: upstream 1.30 has it natively (Zimbra back-ported it for the 2026-06 fix)
#    - hand-ported hunks: see the port patch
cd nginx
for p in $PATCHES; do
  patch -p1 -F0 -s --no-backup-if-mismatch < "$W/zpkg/thirdparty/nginx/patches/$p.patch" >/dev/null || true
done
find . \( -name '*.rej' -o -name '*.orig' \) -delete
[ "${STOP_AFTER_PATCHES:-0}" = 1 ] && { echo "patched base tree: $W/nginx"; exit 0; }

# 2) our port of the rejected hunks (+ the one return-value bug in zm_lookup)
patch -p1 -F0 --dry-run -s < "$HERE/zimbra-nginx-$NGINX_VER-port.patch"
patch -p1 -F0 -s < "$HERE/zimbra-nginx-$NGINX_VER-port.patch"

# 3) modules
mkdir -p modules
git_pin "$W/keepalive" "$KEEPALIVE_URL" "$KEEPALIVE_COMMIT"
rm -rf "$W/keepalive/.git"; cp -r "$W/keepalive" modules/nviennot-nginx-tcp-keepalive
cp -r "$W/zpkg/thirdparty/nginx/zmmodules" zmmodules
[ "$MODE" = prepare ] && { echo "prepared tree: $W/nginx"; exit 0; }

# 4) headers for OpenSSL / SASL, unversioned link names for the runtime libs
cd "$W"
fetch "openssl-$OPENSSL_VER.tar.gz" "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VER/openssl-$OPENSSL_VER.tar.gz" "$OPENSSL_SHA256"
fetch "cyrus-sasl-$SASL_VER.tar.gz" "https://github.com/cyrusimap/cyrus-sasl/releases/download/cyrus-sasl-$SASL_VER/cyrus-sasl-$SASL_VER.tar.gz" "$SASL_SHA256"
tar xzf "openssl-$OPENSSL_VER.tar.gz" && (cd "openssl-$OPENSSL_VER" && ./Configure >/dev/null && make build_generated >/dev/null)
tar xzf "cyrus-sasl-$SASL_VER.tar.gz"
mkdir -p hdr/sasl lib
cp "cyrus-sasl-$SASL_VER"/include/*.h hdr/sasl/ && cp "cyrus-sasl-$SASL_VER/include/md5global.h" hdr/
for l in sasl2 ssl crypto; do ln -sf "$(ls /opt/zimbra/common/lib/lib$l.so.* | head -1)" "lib/lib$l.so"; done

# 5) configure/make: same options as Zimbra's nginx.spec. -Wno-error: Zimbra's modules were
#    written for gcc 11 era warnings (-O2 instead of Zimbra's -O0 -g).
cd "$W/nginx"
./configure --prefix=/opt/zimbra/common \
  --with-cc-opt="-g -O2 -Wno-error -I$W/openssl-$OPENSSL_VER/include -I$W/hdr -I/opt/zimbra/common/include" \
  --with-ld-opt="-Wl,-rpath,/opt/zimbra/common/lib -L$W/lib -L/opt/zimbra/common/lib" \
  --with-debug --with-http_ssl_module --with-http_stub_status_module --with-http_v2_module --with-http_sub_module \
  --with-pcre --with-mail --with-mail-sasl --with-mail_ssl_module \
  --error-log-path=/opt/zimbra/log/nginx.log --http-log-path=/opt/zimbra/log/nginx.access.log \
  --http-client-body-temp-path=/opt/zimbra/data/tmp/nginx/client --http-proxy-temp-path=/opt/zimbra/data/tmp/nginx/proxy \
  --http-fastcgi-temp-path=/opt/zimbra/data/tmp/nginx/fastcgi --without-http_scgi_module --without-http_uwsgi_module \
  --add-module=modules/nviennot-nginx-tcp-keepalive --add-module=zmmodules/http/sso \
  --add-module=zmmodules/http/upstreamzmauth --add-module=zmmodules/mail/zmauth --add-module=zmmodules/mail/throttle \
  > "$W/configure.log" 2>&1 || { tail -40 "$W/configure.log"; exit 1; }
make -j"$(nproc)" > "$W/make.log" 2>&1 || { grep -E "error:|\*\*\*|undefined reference" "$W/make.log" | head -30; exit 1; }
mkdir -p "$OUT" && cp objs/nginx "$OUT/nginx"
"$OUT/nginx" -V 2>&1 | head -2
