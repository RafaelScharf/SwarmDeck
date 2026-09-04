## Agent skills

### Issue tracker

GitHub (issues live in the repo's GitHub Issues; PRs are not a request surface). See `docs/agents/issue-tracker.md`.

### Triage labels

Default labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context repo layout. See `docs/agents/domain.md`.

## Git & PR Workflow

- **Default / Production branch**: `main` is the stable, release-ready branch.
- **Integration branch**: `dev` is the active development and integration branch.
- **Branching**:
  - Always branch off `dev` (`git checkout dev && git pull origin dev && git checkout -b feat/<issue-id>-<slug>`).
  - Use prefixes: `feat/`, `fix/`, `prototype/`, `docs/`, `refactor/`.
- **Pull Requests**:
  - **All PRs must target `dev`**: `gh pr create --base dev --head <branch> --title "..." --body "..."`. Never target `main` directly for feature/task PRs.
  - Link corresponding issues using `Resolves #<issue-id>` or `Part of #<map-id>`.
  - Validate clean compilation (`swift build`) before submitting or merging PRs.
- **Releases to `main`**:
  - Only merged from `dev` into `main` when milestones or prototypes are validated and stable.
