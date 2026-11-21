# CI contract. Agents, the pre-push hook and `ship` all run `just check`.
# Kit: .ci/ (vendored with ci-sync; `just ci-drift` shows drift).
# No GitHub Actions: checks run only on this Mac, and site/ deploys by hand
# with `just deploy-site`.
set shell := ["bash", "-euo", "pipefail", "-c"]

check:
    .ci/bin/ci-par analyzer pester site gitleaks

# PSScriptAnalyzer on the .ps1/.psm1/.psd1 files changed since origin/main plus
# uncommitted work, and the site asset check when site/ changed. No Pester.
check-fast:
    #!/usr/bin/env bash
    set -euo pipefail
    base="$(git merge-base origin/main HEAD)"
    mapfile -t files < <({ git diff --name-only --diff-filter=d "$base"; git ls-files --others --exclude-standard; } | sort -u)
    if [ "${#files[@]}" -eq 0 ]; then echo "check-fast: no changes"; exit 0; fi
    for f in "${files[@]}"; do
      case "$f" in
        *.ps1|*.psm1|*.psd1) pwsh -NoProfile -File tools/Invoke-ToolkitGate.ps1 -Path "$f" -SkipTests ;;
      esac
    done
    if printf '%s\n' "${files[@]}" | grep -q '^site/'; then just site; fi

# No formatter is configured.
fix:
    @echo "fix: no autofixers in this repo"

test: pester

# tools/Invoke-ToolkitGate.ps1, split in two so they run in parallel.
# Needs pwsh with PSScriptAnalyzer and Pester 5 installed.
analyzer:
    pwsh -NoProfile -File tools/Invoke-ToolkitGate.ps1 -SkipTests

pester:
    pwsh -NoProfile -File tools/Invoke-ToolkitGate.ps1 -SkipAnalyzer

# Every local asset site/index.html references exists.
site:
    #!/usr/bin/env bash
    set -euo pipefail
    missing=0
    while IFS= read -r r; do
      [ -n "$r" ] || continue
      path="site/${r%%\?*}"
      if [ -f "$path" ]; then echo "  ok       $r"; else echo "error: index.html references $r but $path does not exist"; missing=1; fi
    done < <(grep -ohE '(href|src)="[^"]+"' site/index.html | sed -E 's/.*="([^"]+)".*/\1/' | grep -vE '^(https?:|//|#|mailto:|data:)' || true)
    [ "$missing" -eq 0 ] && echo "all referenced assets present"
    exit "$missing"

# Publish site/ to the Cloudflare Pages project `tweakeazy` (production).
# Needs Cohen's yes. `--branch=main` marks it production (without --branch,
# wrangler uses the current git branch). Uses wrangler login or CLOUDFLARE_* env.
# Wrangler uploads the working tree, so refuse anything but a clean origin/main.
deploy-site: site
    git fetch -q origin main
    test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" || { echo "deploy-site: check out origin/main first" >&2; exit 1; }
    test -z "$(git status --porcelain --untracked-files=all --ignored=matching -- site)" || { echo "deploy-site: site/ has local changes" >&2; exit 1; }
    npx --yes wrangler@4 pages deploy site --project-name=tweakeazy --branch=main

# Full history, with the repo's .gitleaks.toml when there is one.
gitleaks:
    .ci/bin/ci-gitleaks

ci-drift:
    .ci/bin/ci-sync --check .

# Whole history (nightly).
gitleaks-full:
    .ci/bin/ci-gitleaks --full
