#!/usr/bin/env bash
# Sign-in details for every person in the story.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
d="meridian-mutual.example"
say "${c_bold}Sign in at $STUDIO_URL${c_off}"
say ""
printf '  %-14s %-34s %-34s %s\n' "WHO" "ROLE IN THE STORY" "EMAIL" "PASSWORD"
printf '  %-14s %-34s %-34s %s\n' "Priya Nair"   "Head of AI Platform (admin)"   "priya.nair@$d"   "$WS_ADMIN_PASSWORD"
printf '  %-14s %-34s %-34s %s\n' "Dana Okafor"  "Developer, Claims UK"          "dana.okafor@$d"  "$WS_USER_PASSWORD"
printf '  %-14s %-34s %-34s %s\n' "Tom Reyes"    "Claims handler (chat only)"    "tom.reyes@$d"    "$WS_USER_PASSWORD"
printf '  %-14s %-34s %-34s %s\n' "Sofia Keller" "Developer, Claims EU"          "sofia.keller@$d" "$WS_USER_PASSWORD"
printf '  %-14s %-34s %-34s %s\n' "Marcus Bell"  "CISO (auditor from Act 7)"     "marcus.bell@$d"  "$WS_USER_PASSWORD"
printf '  %-14s %-34s %-34s %s\n' "Elena Rossi"  "FinOps lead (viewer from Act 7)" "elena.rossi@$d" "$WS_USER_PASSWORD"
say ""
say "These passwords were generated for this machine only and live in .env (gitignored)."
