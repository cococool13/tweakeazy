# CI contract. Agents, the pre-push hook and `ship` all run `just check`.
# Kit: .ci/ (vendored with ci-sync; `just ci-drift` shows drift).
# GitHub Actions still run here too (public repo): ci.yml runs the same gate on
# ubuntu and windows, and deploy-site.yml publishes site/ from main.
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

# ci.yml: tools/Invoke-ToolkitGate.ps1, split in two so they run in parallel.
# Needs pwsh with PSScriptAnalyzer and Pester 5 installed.
analyzer:
    pwsh -NoProfile -File tools/Invoke-ToolkitGate.ps1 -SkipTests

pester:
    pwsh -NoProfile -File tools/Invoke-ToolkitGate.ps1 -SkipAnalyzer

# deploy-site.yml: every local asset site/index.html references exists.
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

# Full history, with the repo's .gitleaks.toml when there is one.
gitleaks:
    gitleaks git --no-banner --redact .

ci-drift:
    .ci/bin/ci-sync --check .
