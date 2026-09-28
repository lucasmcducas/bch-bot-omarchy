# BCH × Omarchy Plugin — Collaborative LLM Build Plan

> **Date:** 2026-09-19 · **Author:** Jav (Hermes) · **Status:** ready for review
> **TL;DR:** A way for BCH community members (each with their own LLM agents and compute) to collaboratively build the BCH wallet Omarchy plugin via shared GitHub branches + pull requests, with a clear ownership model.

---

## 1. What's already done (the foundation)

Three repos exist with the building blocks for collaborative work:

| Repo | Path | What it has |
|---|---|---|
| **bch-bot** | `github.com/lucasmcducas/bch-bot-public` | Working BCH wallet — Node.js + libauth, 216 passing tests, encrypted at rest, on `bch-bot-public` master branch |
| **bch-bot-omarchy-plugin** | `github.com/lucasmcducas/bch-bot-omarchy` (local-only, **not pushed yet**) | Initial Omarchy plugin scaffold — manifest, bar widget, IPC command, README, LICENSE, SECURITY.md. Branch: `main`. Head: `20ea2c9` |
| **memory-bch-wiki** | `github.com/lucasmcducas/ai-workspace-backup` | Knowledge base — Omarchy distro + marketplace entity docs, security KB (4 docs) on `security/kb-init` branch, capital accumulation strategy |

**Wiki pages most relevant for collaborators:**
- `entities/omarchy.md` — what Omarchy is
- `entities/omarchy-plugin-marketplace.md` — verified manifest schema, submission workflow, security baseline
- `security/script-and-signing.md`, `utxo-and-mempool.md`, `wallet-threat-model.md`, `cashtokens.md` — security KB

---

## 2. The collaboration model

### Two questions you asked, answered directly

**Q: "Should we share the git to the other LLMs and then they do pull requests?"**

**A: Yes, exactly.** Git forks + PRs is the proven collaborative dev model. Each LLM works on a fork owned by the BCH community member; PRs flow back to `lucasmcducas/bch-bot-omarchy` for review and merge.

**Q: "Do we already have a branch?"**

**A: The plugin repo has only `main` so far. We need a `collaborate/v0.x` branch as the integration branch for community contributions.**

### Why forks + PRs beats a shared monorepo

| Model | Verdict |
|---|---|
| **Shared monorepo with multiple writers** | Rejected. Each LLM running `git push --force` would step on others. Audit trail breaks. |
| **Multiple branches on the same repo** | Rejected. Same trust problem; community members can't grant themselves write access. |
| **Forks + PRs to a shared upstream** | **Chosen.** Each contributor owns their fork; PRs are reviewed before merging. GitHub's review tools, CI, and discussion threads all work natively. |

### Repository structure (target)

```
lucasmcducas/bch-bot-omarchy       ← upstream (you + Jav as maintainers)
├── main                            ← released versions only
├── collaborate/v0.1                ← integration branch for community PRs
├── collaborate/v0.1-bar-widget     ← topic branch for bar widget work
├── collaborate/v0.1-commands       ← topic branch for IPC commands
├── collaborate/v0.1-preview       ← topic branch for visual assets
└── collaborate/v0.1-tests          ← topic branch for QML/test harness

<community-member>/bch-bot-omarchy  ← each member's fork
└── feature/<name>                  ← their working branch
```

---

## 3. Roles + responsibilities

| Role | Who | What they do |
|---|---|---|
| **Upstream maintainer** | You (Luke) + Jav | Merge PRs, cut releases, manage the marketplace submission |
| **Wiki steward** | You + whoever wants to own it | Triage new wiki pages, resolve contradictions, prune stale content |
| **Compute contributor** | BCH community members with idle compute | Run LLM agents that do specific scoped work (one issue = one PR) |
| **Reviewer** | Any maintainer + trusted reviewers | Read PR diffs, run the plugin in their own Omarchy install, request changes |

### Why "compute contributors" is the right framing

A BCH community member with idle GPU/CPU cycles isn't doing the work themselves — their LLM agent is. The community member's role is:
1. **Set up the sandbox** (their machine, their LLM API budget, their GitHub credentials)
2. **Approve the LLM's PRs before they go upstream** (the human reviews what the LLM produced)
3. **Run the resulting code on real Omarchy** (or report what they tried)

This keeps the trust boundary clean: humans review, LLMs draft, humans approve.

---

## 4. First-week plan — what to actually do

### Day 1 (today): Set up the shared infrastructure

1. **Create the GitHub org or repo** — push `~/bch-bot-omarchy-plugin` to `github.com/lucasmcducas/bch-bot-omarchy` (one `gh repo create` command, ~30 sec)
2. **Create the `collaborate/v0.1` branch** from `main` and push it
3. **Add a `COLLABORATION.md`** to the repo root describing the model (fork → branch → PR)
4. **Add a `CONTRIBUTING.md`** with the exact commands a contributor runs
5. **Add issue templates** for the scoped work units (5 of them, listed below)

### Day 2-3: Publish the 5 scoped work units as GitHub issues

Each issue is a self-contained, estimable unit that one LLM agent can finish in a few hours:

| # | Issue title | What it delivers | Acceptance criteria |
|---|---|---|---|
| **#1** | Wire `bch-bot balance` into the bar widget | Real Quickshell `Process` call → JSON parse → balance display in `BchBalanceWidget.qml` | Bar shows live BCH balance updating every 60s; no network code in QML |
| **#2** | Send modal with fee breakdown | Click bar icon → modal shows recipient, amount, network fee, total; confirm button calls `bch-bot send` | Confirmation gates on `BCH_CONFIRM=yes` |
| **#3** | QR code generator for receive | `omarchy bch-wallet receive` shows QR for the wallet's current receiving address | QR encodes the address; works in shell command output |
| **#4** | preview.png + marketplace submission prep | Screenshot of the bar widget, cropped to 1200x630, pushed to repo | File exists at repo root, ≤50MB |
| **#5** | Submit the marketplace listing | Open the GitHub issue at `omacom/omarchy-plugin-marketplace` with the proper body | Issue opened with all 5 checklist items confirmed |

### Day 4-7: First wave of contributions

Each community member picks one issue. Their LLM works it. PRs flow in.

---

## 5. Contributor setup — what each BCH member does

```bash
# 1. Fork the repo on GitHub (one click)

# 2. Clone their fork
git clone https://github.com/<their-handle>/bch-bot-omarchy.git
cd bch-bot-omarchy
git remote add upstream https://github.com/lucasmcducas/bch-bot-omarchy.git
git fetch upstream
git checkout -b collaborate/v0.1 upstream/collaborate/v0.1
git checkout -b feature/<issue-number>-<short-name>

# 3. Make the LLM aware of context
#    Point their LLM at:
#      - this MD file
#      - entities/omarchy-plugin-marketplace.md (manifest schema)
#      - SECURITY.md (the marketplace baseline)
#      - lib/wallet-encryption.mjs (from bch-bot, for understanding)

# 4. LLM does the work, pushes commits
git add -A
git commit -m "fix(#1): wire bch-bot balance into bar widget via Quickshell.Io"
git push origin feature/1-balance-display

# 5. Human reviews the diff on GitHub, opens PR to lucasmcducas/bch-bot-omarchy collaborate/v0.1
```

### What the LLM needs to know (give them this exact list)

1. **Plugin ID** is `io.github.lucasmcducas.bch-wallet` — do not change this.
2. **Manifest schema** is `schemaVersion: 1` with `kinds`, `entryPoints`, optional kind-specific config block.
3. **Security baseline** blocks `curl|sh`, unpinned git exec, passwordless sudoers, bundled binaries, dangerous `/tmp` use. The plugin does none of these — but the LLM should not introduce any.
4. **Quickshell API** for IPC: `Quickshell.Io.Process` for spawning the CLI; `Quickshell.Io.IpcHandler` for receiving commands. The QML needs testing in a real Omarchy install to verify.
5. No built-in fee. Send confirmation shows network fee only.
6. **No write access outside plugin scope** — do not modify `~/.config/omarchy/` outside the plugin's own settings.
7. **Test before PR** — `node scripts/test-*.mjs` style tests are encouraged for any logic the QML defers to.

---

## 6. The wiki is the shared brain

The BCH wiki (`memory-bch-wiki` on the `security/kb-init` branch) is what every LLM should read first. To make it discoverable to community LLMs:

1. **Mirror the wiki** as a public repo (currently it's in `lucasmcducas/ai-workspace-backup`, which contains unrelated content). Better: extract the BCH-relevant subset into `lucasmcducas/bch-wiki` and make it public.
2. **Add a `BOOTSTRAP.md`** at the wiki repo root with:
   - The 5-10 most important pages to read
   - The collaboration model + link to this plan
   - How to submit wiki changes (PR to wiki, not just commits)
3. **Reference the wiki from the plugin repo** — `README.md` should link to the relevant entity pages.

---

## 7. Risk model — what could go wrong

| Risk | Likelihood | Mitigation |
|---|---|---|
| Two LLMs edit the same file, conflicts in PR | High | Work in different files when possible; one issue = one PR; small scope per PR |
| LLM introduces a security baseline violation | Medium | Maintainer review with the baseline checklist; CI lint that greps for `curl|sh` patterns |
| LLM leaks a wallet private key in a PR | Low | The plugin repo has no wallet. The bch-bot repo has the wallet code; tests use ephemeral keys. Document this. |
| Marketplace rejection after submission | Medium | Read SUBMISSION.md + SECURITY.md carefully before submitting; preview the issue body before opening it |
| Contributor adds a hidden fee or third-party destination | Medium | No fee of any kind in the public plugin. PRs that add one need explicit maintainer approval |

---

## 8. What "done" looks like for v0.1

- [ ] `bch-bot-omarchy` is on GitHub (public)
- [ ] `collaborate/v0.1` branch exists with the scaffold
- [ ] `COLLABORATION.md` + `CONTRIBUTING.md` at repo root
- [ ] 5 GitHub issues published, one per work unit
- [ ] First PR from a community member merged
- [ ] Plugin tested in a real Omarchy 4.0 install
- [ ] `preview.png` generated
- [ ] Marketplace submission issue opened

After v0.1 ships, v0.2 candidates:
- PUSD stake widget
- Cauldron LP widget (real-time pool value)
- Multi-wallet support
- Hardware wallet integration (Ledger/Trezor via PSBT)
- Token NFT gallery (read-only, no signing)

---

## 9. The 5 things you should approve before I execute

1. **Push `~/bch-bot-omarchy-plugin` to GitHub as `lucasmcducas/bch-bot-omarchy`** (creates the public repo)
2. **Create `collaborate/v0.1` integration branch** and push the COLLABORATION.md + CONTRIBUTING.md + issue templates
3. **Mirror the bch wiki to a public repo** (`lucasmcducas/bch-wiki`) with a BOOTSTRAP.md
4. **Open the 5 GitHub issues** (one per work unit, with acceptance criteria from §4)
5. **Send the invite to BCH community members** with a short message + this plan attached

Each is independently reversible. I'll wait for your go on the first before doing the rest.

---

## 10. Appendix: One-paragraph pitch for community members

> We're building the first spendable crypto plugin for the Omarchy Plugin Marketplace — a self-custodial Bitcoin Cash (BCH) wallet in your Omarchy bar. The wallet code (`bch-bot`) is at `github.com/lucasmcducas/bch-bot-public` (Node.js, 216 tests passing). The plugin scaffold is at `github.com/lucasmcducas/bch-bot-omarchy`. We need community help on 5 scoped work units (wire balance display, send modal with fee disclosure, QR generator, preview screenshot, marketplace submission). Each unit is one issue = one PR. Fork the repo, point your LLM at this plan + the wiki entities, review the diff, open the PR. Maintainers (Luke + Jav) review + merge. MIT-licensed, no vendor lock-in.
