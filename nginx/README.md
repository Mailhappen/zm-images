# nginx 1.30.7 for Zimbra's proxy

Zimbra 10.1.x ships its own nginx **1.24.0** (`zimbra-nginx`, used as the mail/web proxy). The nginx
advisory of 2026-11-18 (CERT.at, F5; fixed upstream in 1.30.7 / 1.31.9) affects it:

| CVE | Component | Exposed on a Zimbra proxy |
|---|---|---|
| CVE-2026-113425 | mail proxy (`auth_http`), use-after-free, no login needed | **yes**: IMAP/POP3 on 110/143/993/995 |
| CVE-2026-123007, -123633 | HTTP/2 | only if the web proxy port is reachable directly |
| CVE-2026-121810 | HTTP/3 | no (not compiled in) |

Zimbra/Maldua had not released a fixed build when this was written. Mitigations other than patching
(restricting the mail ports) were not an option, so this builds nginx 1.30.7 with Zimbra's patch set.

## How it is built

Zimbra's nginx = vanilla nginx tarball + 23 patches + 5 modules
([Zimbra/packages](https://github.com/Zimbra/packages), `thirdparty/nginx`). The patches target 1.24.0.

`build-nginx.sh` fetches everything pinned (sha256 / git commit hash verified), applies Zimbra's
patches with zero fuzz, drops the rejects, then applies `zimbra-nginx-1.30.7-port.patch`, which is our
hand-port of what was rejected. Nothing of Zimbra's is copied into this repository.

Port patch, in short:

* `--with-mail-sasl` option variables, `version=` parameter of `upstream { server }`, `exact_version_check`,
  the upstream `connect` hook, the `ssl_session_reuse` guard
* mail proxy: SASL includes, AUTH PLAIN/LOGIN abort (`*`) and length checks, IMAP parser state
  names (`swi_*`) + RFC 3501 backslash rule, IMAP upstream response parsing (ID, `[ALERT]`, optional
  untagged responses)
* bug fix in Zimbra's `ngx_zm_lookup.c`: `return;` in a non-void function -> `ZM_LOOKUP_SSL_EVENT_FAILED`

* upstream keepalive: nginx >= 1.29.7 enables it implicitly (32 connections). With it, the keepalive peer init
  wraps Zimbra's asynchronous `zmauth` peer init and turned its `NGX_AGAIN` ("route lookup pending") into an
  error: **every authenticated web/DAV request got a 500**, anonymous ones still worked. The port keeps the
  implicit keepalive off (as in 1.24; an explicit `keepalive N` still works) and passes `NGX_AGAIN` through.

Deliberately **not** ported: `max_headers` (native in nginx 1.30; Zimbra back-ported it for CVE-2026-49975),
and the removal of `ngx_ssl_ocsp_cleanup()` in `ngx_event_openssl.c` (Zimbra does not use OCSP stapling).

Build differences to Zimbra's package: `-O2` instead of `-O0`, `-Wno-error` (Zimbra's modules trigger
warnings with a current gcc).

## Things that bite

* **File capability.** The stock binary has `cap_net_bind_service=ep` (the zimbra user binds 110/143/993/995).
  Replacing the file drops it: `nginx: [emerg] bind() to [::]:143 failed (13: Permission denied)`.
  Dockerfile.nginx-patch sets it again, and so must a manual swap: `setcap cap_net_bind_service=+ep .../nginx`.
* The binary is linked against Zimbra's OpenSSL (`/opt/zimbra/common/lib`), so it must be built in a stage that
  has those libs (Dockerfile.nginx-patch builds from your existing image).
* `nginx: [warn] the "listen ... http2" directive is deprecated` is harmless (Zimbra's templates use the 1.24 syntax).

## Hot swap in a running container (no image rebuild)

```sh
N=/opt/zimbra/common/sbin/nginx
docker exec zimbra cp -a $N $N.1.24.0.bak
docker cp ./nginx zimbra:$N.new
docker exec zimbra bash -c "chown root:zimbra $N.new && chmod 750 $N.new && setcap cap_net_bind_service=+ep $N.new && $N.new -t -c /opt/zimbra/conf/nginx.conf && mv -f $N.new $N"
docker exec -u zimbra zimbra /opt/zimbra/bin/zmproxyctl restart      # about 2 minutes without IMAP/POP3
```

Lost when the container is recreated from an image that does not contain the patch.

## Tested (1.24.0 vs 1.30.7 against the real config, same results)

`nginx -t` on the real config; second instance on ports +20000 against the live mailbox: IMAP LOGIN, SASL-IR,
AUTHENTICATE PLAIN (with and without challenge), literal password, ID, STARTTLS, wrong password, SASL abort,
bad backslash, oversize username; POP3 USER/PASS and AUTH PLAIN; web over HTTP/1.1 and HTTP/2, **anonymous and
authenticated** (SOAP auth, `ZM_AUTH_TOKEN` cookie on `/` and `/mail`, SOAP with token, DAV PROPFIND with Basic
auth). Smoke load: 400 parallel cookie requests over HTTP/2 + 200 parallel DAV requests, no errors, no worker crash.
HTTP/3 is terminated by the front proxy (nginx here has no HTTP/3). **Not tested:** the exploits themselves,
long-run behaviour.

Always test **authenticated** requests; the login page alone does not exercise the route lookup.

## Remove

Once Zimbra ships a build with an nginx >= 1.30.7 / 1.31.9 (check `nginx -v` inside the image), delete the
`nginx-build` stage and the `COPY --from=nginx-build` step in `Dockerfile.nginx-patch` and this directory.

## Build

```sh
docker build -f Dockerfile.nginx-patch --build-arg BASE_IMAGE=yeak/zimbra-aio:<version> -t yeak/zimbra-aio:<version>-nginx1.30.7 .
```
