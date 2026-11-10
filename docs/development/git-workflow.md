
# Git Workflow

This document describes the Git branching and tagging conventions used by RaviOS.

## Branches

RaviOS uses a lightweight branch strategy to keep the main development history stable while allowing independent development.

### `main`

The primary project branch.

- Contains stable, integrated project changes.
- Should remain buildable and reasonably tested.
- Milestones and completed development work are merged back into this branch.

### `develop/*`

Development branches for individual features or work areas.

Examples:

- `develop/docker-engine`
- `develop/web-dashboard`
- `develop/application-manager`

Development branches allow features to evolve independently before being integrated into `main`.

## Tags

Tags mark important, stable points in the project's history.

Milestone tags use the following naming convention:

`milestone/<milestone-name>`

Examples:

- `milestone/ssh-foundation`
- `milestone/docker-engine`
- `milestone/first-bootable-release`

Annotated tags are preferred because they include a description and metadata.

Tags should point to commits that represent meaningful and verified project milestones.

## Creating a milestone

To create an annotated milestone tag:

```bash
git tag -a milestone/ssh-foundation -m "RaviOS milestone: bootable x86_64 system with working SSH access"
```

To publish the tag:

```bash
git push origin milestone/ssh-foundation
```

## Starting a development branch

Create a new development branch from the desired starting point:

```bash
git switch main
git switch -c develop/docker-engine
```

Publish it to the remote repository:

```bash
git push -u origin develop/docker-engine
```

To start a branch from a specific milestone:

```bash
git switch -c develop/alternative-design milestone/ssh-foundation
```

## Returning to a milestone

To inspect or restore a previous project state:

```bash
git switch --detach milestone/ssh-foundation
```

To create a new branch from that milestone:

```bash
git switch -c develop/alternative-design milestone/ssh-foundation
```

## General conventions

- Do not use `main` for experimental development.
- Use descriptive branch names with the `develop/` prefix.
- Create annotated tags for meaningful milestones.
- Do not move or overwrite published milestone tags.
- Keep commits focused and use descriptive commit messages.
- Preserve milestone tags as permanent references to verified project states.
