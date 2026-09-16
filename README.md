# FCED 2026/2027 — group repository

Group: **gNN** · Members: *(name, number, GitHub username)*

This repository is the single place where all work for this unit lives: lab deliverables,
the `Vagrantfile`, Ansible code, container definitions, monitoring configuration and the
project report. It is read as evidence — the tree **and** the commit history.

## First session

1. Every member clones this repository and sets the group number before the first boot:

   ```bash
   git clone git@github.com:fced2627/gNN.git && cd gNN
   export FCED_GROUP=NN          # put this in your shell profile
   cd lab-env && vagrant up
   ```

2. Build the repository skeleton together, as described in §3 of the starter guide
   (`ansible/`, `images/`, `containers/`, `monitoring/`, `docs/`) and agree out loud on
   branch strategy, review and commit conventions.

3. Replace this section with your own twenty-line "what this is and how to build it".

## Rules that are graded

- **One directory per lab**: `labNN/`. A lab with no `README.md` explaining how to run it
  counts as not delivered.
- **Commit as you go.** Three commits by three people beats one commit at 23:58.
- **Nothing secret in git**: no private keys, no passwords, no certificates. Ansible Vault
  from module 05 onwards; until then keep secrets out of the repository entirely.
- **The `Vagrantfile` is yours now.** Changing it is expected, and the changes are part of
  what is assessed.

## What is already here

| Path | What it is |
|---|---|
| `lab-env/Vagrantfile` | The four-machine cluster, as code |
| `lab-env/nodes-pxe.sh` | Diskless compute nodes, plus the BMC wrapper (`start`/`stop`/`reset`/`console`) |
| `lab-env/README.md` | Provider matrix, setup and troubleshooting |
| `.gitignore` | Vagrant, Ansible and container artefacts that must never be committed |
