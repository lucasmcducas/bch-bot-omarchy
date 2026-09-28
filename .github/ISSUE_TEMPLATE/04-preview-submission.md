name: Issue #4 — preview.png + marketplace submission prep
description: Generate preview.png (screenshot of bar widget), open the marketplace submission issue.
labels: ["help wanted", "release"]
assignees: []
---

# preview.png + marketplace submission prep

## Goal

Two deliverables:
1. **preview.png** at repo root — a screenshot of the bar widget in action, sized for the marketplace card (1200x630, ≤50MB, ≤40MP)
2. **Marketplace submission issue** — open the GitHub issue at `omacom/omarchy-plugin-marketplace` with the proper body

## Acceptance criteria

- [ ] `preview.png` exists at repo root
- [ ] Resolution between 1200x630 and 4096x4096
- [ ] Shows the bar widget (balance visible, with a sample wallet loaded)
- [ ] Marketplace submission issue opened at `omacom/omarchy-plugin-marketplace`
- [ ] Issue body matches the [SUBMISSION.md](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/SUBMISSION.md) template exactly
- [ ] All 5 checklist items confirmed
- [ ] Plugin ID `io.github.lucasmcducas.bch-wallet` matches

## Implementation hint

For `preview.png`:
- Take a screenshot in Omarchy 4.0 with the bar widget active
- Crop to 1200x630 (or 16:9) using `magick`, `ffmpeg`, or your editor
- Save as `preview.png` at repo root

For the marketplace submission:
- Read [SUBMISSION.md](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/SUBMISSION.md) first
- Use the exact 6-heading structure (Repository URL, Category, Tags, Suggest a missing tag, Maintainer notes, Submission checklist)
- Pick one Category (recommend `Widgets` or `Productivity`)
- Pick 1-3 Tags (recommend `bar`, `quickshell`, `system`)

## Out of scope

- README polish (separate)
- Marketplace verification (after initial submit)

## Resources

- [Omarchy marketplace SUBMISSION.md](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/SUBMISSION.md)
- Issues #1, #2, #3 should be merged first so the preview is meaningful
- Wiki: https://github.com/lucasmcducas/bch-wiki-public/entities/omarchy-plugin-marketplace.md

## Workflow

1. Wait for issues #1, #2, #3 to be merged (the preview should reflect real functionality)
2. Comment on this issue to claim it
3. Generate preview.png + open marketplace submission issue
4. Submit a PR with both deliverables (the PNG and a link to the marketplace issue)
5. Open PR with `Closes #4`
