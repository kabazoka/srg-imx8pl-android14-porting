#!/bin/bash
#
# diff-build-tree.sh — Compare build tree vs clean repo to find untracked modifications
#
# Usage: ./diff-build-tree.sh [--phase1-only] [--phase2-only]
#
# Phase 1: git status in each sub-repo (finds uncommitted changes)
# Phase 2: git diff HEAD vs clean repo HEAD (finds committed differences)
#
# Outputs report to reference/notes/build_tree_diff_report.txt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

CURRENT="/mnt/data/imx-android-14.0.0_2.2.0/android_build"
CLEAN="/mnt/data/imx-android-14.0.0_2.2.0_evk/imx-android-14.0.0_2.2.0/android_build"
REPORT="$REPO_ROOT/reference/notes/build_tree_diff_report.txt"

# Directories to compare (relative to android_build)
DIRS=(
    "vendor/nxp-opensource/kernel_imx"
    "vendor/nxp-opensource/uboot-imx"
    "vendor/nxp-opensource/arm-trusted-firmware"
    "vendor/nxp-opensource/imx-mkimage"
    "vendor/nxp-opensource/imx-gki"
    "vendor/nxp-opensource/imx"
    "device/nxp"
)

# Parse args
RUN_PHASE1=true
RUN_PHASE2=true
for arg in "$@"; do
    case "$arg" in
        --phase1-only) RUN_PHASE2=false ;;
        --phase2-only) RUN_PHASE1=false ;;
        -h|--help)
            echo "Usage: $0 [--phase1-only] [--phase2-only]"
            echo "  --phase1-only   Only run git status check (fast)"
            echo "  --phase2-only   Only run cross-repo HEAD comparison"
            exit 0
            ;;
        *) echo "Unknown arg: $arg"; exit 1 ;;
    esac
done

# Validate paths
for p in "$CURRENT" "$CLEAN"; do
    if [[ ! -d "$p" ]]; then
        echo "ERROR: Directory not found: $p"
        exit 1
    fi
done

mkdir -p "$(dirname "$REPORT")"

# Counters
modified_count=0
only_current_count=0
only_clean_count=0
git_dirty_count=0
committed_diff_count=0

# Start report
{
    echo "========================================"
    echo "Build Tree Diff Report"
    echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Current:  $CURRENT"
    echo "Clean:    $CLEAN"
    echo "========================================"
    echo ""
} > "$REPORT"

# ─── Phase 1: Git Status (uncommitted changes) ────────────────────────
if $RUN_PHASE1; then
    echo "=== Phase 1: Git Status (uncommitted changes) ==="
    {
        echo "=== Phase 1: Git Status (uncommitted changes) ==="
        echo ""
    } >> "$REPORT"

    for dir in "${DIRS[@]}"; do
        full="$CURRENT/$dir"
        if [[ ! -d "$full" ]]; then
            echo "  SKIP (not found): $dir"
            continue
        fi

        git_root=""
        if git -C "$full" rev-parse --show-toplevel &>/dev/null; then
            git_root="$(git -C "$full" rev-parse --show-toplevel)"
        else
            echo "  SKIP (not a git repo): $dir"
            echo "--- $dir --- (not a git repo, skipped)" >> "$REPORT"
            echo "" >> "$REPORT"
            continue
        fi

        echo "  Checking: $dir"

        # git status (staged + unstaged + untracked)
        status_output="$(git -C "$git_root" status --short -- "$full" 2>/dev/null || true)"
        # git diff (unstaged working tree changes)
        diff_names="$(git -C "$git_root" diff --name-only -- "$full" 2>/dev/null || true)"

        # Combine
        combined=""
        [[ -n "$status_output" ]] && combined="$status_output"
        if [[ -n "$diff_names" ]]; then
            [[ -n "$combined" ]] && combined="$combined"$'\n'"$diff_names" || combined="$diff_names"
        fi

        {
            echo "--- $dir ---"
            if [[ -z "$combined" ]]; then
                echo "(clean)"
            else
                echo "$combined"
                count=$(echo "$combined" | sort -u | wc -l)
                git_dirty_count=$((git_dirty_count + count))
            fi
            echo ""
        } >> "$REPORT"
    done

    # Show actual diffs for modified (tracked) files
    {
        echo "--- Detailed diffs for modified tracked files ---"
        echo ""
    } >> "$REPORT"

    for dir in "${DIRS[@]}"; do
        full="$CURRENT/$dir"
        [[ ! -d "$full" ]] && continue
        git_root=""
        git -C "$full" rev-parse --show-toplevel &>/dev/null && \
            git_root="$(git -C "$full" rev-parse --show-toplevel)" || continue

        diff_output="$(git -C "$git_root" diff -- "$full" 2>/dev/null || true)"
        if [[ -n "$diff_output" ]]; then
            {
                echo ">>> $dir <<<"
                echo "$diff_output"
                echo ""
            } >> "$REPORT"
        fi
    done

    echo "" >> "$REPORT"
    echo "  Phase 1 done. Found $git_dirty_count dirty entry(s)."
    echo ""
fi

# ─── Phase 2: Cross-repo HEAD comparison ──────────────────────────────
if $RUN_PHASE2; then
    echo "=== Phase 2: Cross-repo HEAD Comparison ==="
    {
        echo "=== Phase 2: Cross-repo HEAD Comparison ==="
        echo "(Compares committed HEAD of build tree vs clean repo)"
        echo ""
    } >> "$REPORT"

    for dir in "${DIRS[@]}"; do
        cur_dir="$CURRENT/$dir"
        cln_dir="$CLEAN/$dir"

        if [[ ! -d "$cur_dir" ]]; then
            echo "  SKIP (not in current): $dir"
            continue
        fi
        if [[ ! -d "$cln_dir" ]]; then
            echo "  SKIP (not in clean): $dir"
            echo "--- $dir --- (not in clean repo)" >> "$REPORT"
            echo "" >> "$REPORT"
            continue
        fi

        # Get git roots
        cur_git=""
        cln_git=""
        git -C "$cur_dir" rev-parse --show-toplevel &>/dev/null && \
            cur_git="$(git -C "$cur_dir" rev-parse --show-toplevel)" || true
        git -C "$cln_dir" rev-parse --show-toplevel &>/dev/null && \
            cln_git="$(git -C "$cln_dir" rev-parse --show-toplevel)" || true

        if [[ -z "$cur_git" || -z "$cln_git" ]]; then
            echo "  SKIP (no git): $dir"
            continue
        fi

        cur_head="$(git -C "$cur_git" rev-parse HEAD 2>/dev/null)"
        cln_head="$(git -C "$cln_git" rev-parse HEAD 2>/dev/null)"

        echo "  Comparing: $dir"
        echo "    Current HEAD: ${cur_head:0:12}"
        echo "    Clean HEAD:   ${cln_head:0:12}"

        {
            echo "--- $dir ---"
            echo "  Current HEAD: $cur_head"
            echo "  Clean HEAD:   $cln_head"
        } >> "$REPORT"

        if [[ "$cur_head" == "$cln_head" ]]; then
            echo "    -> Same HEAD (identical commits)"
            echo "  -> SAME HEAD (no committed differences)" >> "$REPORT"
            echo "" >> "$REPORT"
            continue
        fi

        # Different HEADs — find what diverged
        echo "    -> DIFFERENT HEADs! Checking..."

        # Try to compare by adding the clean repo as a remote temporarily
        # Instead, use diff-tree with --no-index on specific paths
        # More reliable: use git format-patch to show the extra commits

        # Check if clean head exists in current repo
        if git -C "$cur_git" cat-file -t "$cln_head" &>/dev/null; then
            # Clean HEAD is known — show commits between them
            extra_commits="$(git -C "$cur_git" log --oneline "$cln_head..$cur_head" 2>/dev/null || true)"
            missing_commits="$(git -C "$cur_git" log --oneline "$cur_head..$cln_head" 2>/dev/null || true)"

            {
                if [[ -n "$extra_commits" ]]; then
                    echo "  Extra commits in current (not in clean):"
                    echo "$extra_commits" | sed 's/^/    /'
                    committed_diff_count=$((committed_diff_count + $(echo "$extra_commits" | wc -l)))
                fi
                if [[ -n "$missing_commits" ]]; then
                    echo "  Missing commits (in clean but not in current):"
                    echo "$missing_commits" | sed 's/^/    /'
                fi
                echo ""
            } >> "$REPORT"
        else
            # Clean HEAD is not in current repo — do file-level comparison
            # Use rsync --dry-run for a fast comparison (excludes .git)
            echo "    (HEADs not related — falling back to file comparison)"

            diff_result="$(diff -rq \
                --exclude='.git' \
                --exclude='*.o' --exclude='*.ko' --exclude='*.pyc' \
                --exclude='__pycache__' --exclude='*.cmd' --exclude='*.d' \
                --exclude='*.order' --exclude='*.mod' --exclude='*.mod.c' \
                --exclude='*.symvers' --exclude='modules.builtin' \
                --exclude='.tmp_*' --exclude='*.dtb' \
                --exclude='out' --exclude='build' \
                "$cur_dir" "$cln_dir" 2>/dev/null | head -200 || true)"

            if [[ -z "$diff_result" ]]; then
                echo "  -> Files identical despite different HEADs" >> "$REPORT"
            else
                file_count=$(echo "$diff_result" | wc -l)
                echo "  -> $file_count file differences (showing first 200):" >> "$REPORT"
                echo "$diff_result" | sed 's/^/    /' >> "$REPORT"
                committed_diff_count=$((committed_diff_count + file_count))
            fi
            echo "" >> "$REPORT"
        fi
    done

    echo ""
    echo "  Phase 2 done."
    echo ""
fi

# ─── Summary ───────────────────────────────────────────────────────────
{
    echo "========================================"
    echo "Summary"
    echo "========================================"
    if $RUN_PHASE1; then
        echo "  Phase 1 (git dirty entries):    $git_dirty_count"
    fi
    if $RUN_PHASE2; then
        echo "  Phase 2 (committed diffs):      $committed_diff_count"
    fi
    echo "========================================"
} | tee -a "$REPORT"

echo ""
echo "Report saved to: $REPORT"
