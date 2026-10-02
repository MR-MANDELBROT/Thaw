#!/bin/zsh
# Install the newest fork CI build: download the unsigned app, sign it with the
# local Developer ID, back up the installed copy, swap it in and relaunch.
# Usage: fork-install.sh [run-id]
set -euo pipefail
REPO=${THAW_FORK_REPO:-MR-MANDELBROT/Thaw}
BRANCH=${THAW_FORK_BRANCH:-fix/macos27}
DEST=/Applications/Thaw.app
BACKUPS=${THAW_BACKUP_DIR:-$HOME/Developer/Thaw-backups}

run=${1:-}
if [[ -z $run ]]; then
    # Newest unexpired Thaw-unsigned artifact on the branch; the run may still
    # count as failed when only its test job failed.
    run=$(gh api "repos/$REPO/actions/artifacts?name=Thaw-unsigned&per_page=30" \
        --jq "[.artifacts[] | select(.expired == false and .workflow_run.head_branch == \"$BRANCH\")][0].workflow_run.id")
fi
[[ -n $run && $run != null ]] || { echo "error: no Thaw-unsigned artifact on $BRANCH" >&2; exit 1; }
echo "Run $run"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
gh run download "$run" -R "$REPO" -n Thaw-unsigned -D "$work"
ditto -x -k "$work/Thaw-unsigned.zip" "$work"
"${0:A:h}/fork-resign.sh" "$work/Thaw.app"

# Thaw has no SIGTERM handler, but macOS drops its hiding restriction with the
# process, so the bar comes back on its own. A quit Apple Event would need an
# Automation grant.
if pgrep -x Thaw >/dev/null; then
    pkill -TERM -x Thaw || true
    for _ in {1..40}; do pgrep -x Thaw >/dev/null || break; sleep 0.25; done
    pgrep -x Thaw >/dev/null && { echo "error: Thaw did not quit" >&2; exit 1; }
fi

# Move the old bundle aside instead of deleting it: App Management may refuse
# to delete an app signed by another team halfway through. The .bak suffix
# keeps Launch Services from treating the backup as a second Thaw.
if [[ -d $DEST ]]; then
    mkdir -p "$BACKUPS"
    version=$(defaults read "$DEST/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo unknown)
    build=$(defaults read "$DEST/Contents/Info" CFBundleVersion 2>/dev/null || echo 0)
    sha=$(defaults read "$DEST/Contents/Info" GitCommitSHA 2>/dev/null || echo nosha)
    backup="$BACKUPS/Thaw-$version-$build-$sha.app.bak"
    [[ -e $backup ]] && backup="$backup.$(date +%Y%m%d%H%M%S)"
    mv "$DEST" "$backup"
    echo "Backup $backup"
fi

ditto "$work/Thaw.app" "$DEST"
codesign --verify --deep --strict "$DEST"
open "$DEST"
echo "Installed $(defaults read "$DEST/Contents/Info" CFBundleShortVersionString) ($(defaults read "$DEST/Contents/Info" GitCommitSHA))"
