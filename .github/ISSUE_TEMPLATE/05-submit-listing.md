name: Issue #5 — Submit the marketplace listing
description: Final marketplace submission once preview.png + features are ready.
labels: ["help wanted", "release"]
assignees: []
---

# Submit the marketplace listing

## Goal

The plugin is now feature-complete (issues #1-#4 merged). Submit it to the Omarchy Plugin Marketplace.

## Acceptance criteria

- [ ] Repository URL is `https://github.com/lucasmcducas/bch-bot-omarchy`
- [ ] Category is set (recommend `Widgets` or `Productivity`)
- [ ] 1-3 tags set (recommend `bar`, `quickshell`, `system`)
- [ ] `preview.png` exists and meets marketplace requirements (≤50MB, ≤40MP, named correctly)
- [ ] Submission checklist 100% complete
- [ ] Issue body matches SUBMISSION.md template
- [ ] Maintainer (@lucasmcducas or @hermes-agent) approves before issue is opened

## Implementation hint

Before opening the issue:
1. Read [SUBMISSION.md](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/SUBMISSION.md) thoroughly
2. Read [SECURITY.md](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/SECURITY.md) (the baseline)
3. Run `./audit-public.sh` (must pass)
4. Build the issue body locally first, show the maintainer, get explicit approval

The maintainer approval step is critical — the marketplace labels new submissions as `submission`, runs automated checks, and only publishes after explicit `approved-and-verified` maintainer decision.

## Resources

- [SUBMISSION.md](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/SUBMISSION.md)
- [SECURITY.md](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/SECURITY.md)
- Plugin SECURITY.md (in this repo)

## Workflow

1. Wait for issues #1-#4 to be merged
2. Comment on this issue to claim it
3. Draft the submission issue body locally
4. Get explicit maintainer approval (in this repo's issue thread)
5. Open the marketplace submission issue at `omacom/omarchy-plugin-marketplace`
6. Open a PR with `Closes #5` linking to the marketplace issue
