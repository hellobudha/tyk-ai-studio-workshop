#!/usr/bin/env bash
# Create the first admin (Priya) on a fresh AI Studio and save an API key for the scripts.
# On an empty database the first registered user becomes the administrator.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
need curl jq

[ -n "${WS_ADMIN_PASSWORD:-}" ] || die "WS_ADMIN_PASSWORD is empty in .env (run ./workshop up)"

if [ -n "$(get admin.key)" ] && curl -sf -o /dev/null -H "Authorization: Bearer $(get admin.key)" "$STUDIO_URL/common/me"; then
  ok "admin API key already works ($ADMIN_EMAIL)"; exit 0
fi

jar="$(mktemp)"; trap 'rm -f "$jar"' EXIT
csrf="$(curl -sS -D - -o /dev/null -c "$jar" "$STUDIO_URL/csrf-token" | awk 'tolower($1)=="x-csrf-token:"{print $2}' | tr -d '\r')"
[ -n "$csrf" ] || die "no CSRF token from $STUDIO_URL/csrf-token (is AI Studio up?)"

reg="$(jq -cn --arg e "$ADMIN_EMAIL" --arg n "$ADMIN_NAME" --arg p "$WS_ADMIN_PASSWORD" \
  '{data:{type:"users",attributes:{email:$e,name:$n,password:$p,with_portal:true,with_chat:true}}}')"
code="$(curl -sS -o /dev/null -w '%{http_code}' -b "$jar" -c "$jar" -H "X-CSRF-Token: $csrf" \
  -H 'Content-Type: application/json' -X POST "$STUDIO_URL/auth/register" -d "$reg")"
case "$code" in 201) ok "registered first admin $ADMIN_EMAIL";; 400|409) ok "admin already registered";; *) die "register returned HTTP $code";; esac

login="$(jq -cn --arg e "$ADMIN_EMAIL" --arg p "$WS_ADMIN_PASSWORD" '{data:{type:"login",attributes:{email:$e,password:$p}}}')"
# The session cookie can be marked Secure; send it by hand so plain http works.
hdr="$(mktemp)"
out="$(curl -sS -D "$hdr" -b "$jar" -c "$jar" -H "X-CSRF-Token: $csrf" -H 'Content-Type: application/json' \
  -X POST "$STUDIO_URL/auth/login" -d "$login")"
[ "$(printf '%s' "$out" | jq -r '.is_admin // false')" = "true" ] || die "login failed or $ADMIN_EMAIL is not an admin: $out (was this database seeded with a different password? ./workshop reset)"
session="$(awk -F'[=;]' 'tolower($0) ~ /^set-cookie: session=/{print $2}' "$hdr" | tail -1)"; rm -f "$hdr"

key="$(curl -sS -X POST "$STUDIO_URL/common/me/api-key/roll" -H "Cookie: session=$session" -H "X-CSRF-Token: $csrf" -b "$jar" | jq -r '.data.api_key // empty')"
[ -n "$key" ] || die "could not roll an API key"
put admin.key "$key"
ok "admin API key saved to .state/admin.key"
