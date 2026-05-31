# Scrubs Sandboxing Proposal

## Overview

`scrubs` is a proposal for running modern JavaScript and TypeScript development workflows inside an intentionally lower-trust local sandbox.

The motivating concern is simple:

- package managers execute third-party code
- build and test tools execute third-party code
- local development servers execute third-party code
- dependency compromise is a realistic supply-chain risk

The purpose of `scrubs` is not to prove dependencies are safe.

The purpose is to reduce the blast radius when they are not.

## Problem Statement

A common local workflow assumes the developer machine is a safe place to run:

- `npm install`
- `pnpm install`
- `bun install`
- `build`
- `test`
- `dev`

In practice, those actions may execute arbitrary code from:

- direct dependencies
- transitive dependencies
- lifecycle hooks such as `preinstall`, `install`, and `postinstall`
- CLIs invoked during build, test, lint, and development

That means an ordinary dependency upgrade can become a path to local code execution.

If that code runs on the host machine with access to the developer's real environment, it may be able to read and exfiltrate sensitive data.

## Threat Model

### Core Attack Story

The motivating attack looks like this:

1. a package in the dependency graph is compromised
2. the developer upgrades or freshly installs without noticing
3. dependency lifecycle scripts, build steps, test setup, or dev tooling execute attacker code
4. that code reads secrets or personal data available to the process
5. the attacker exfiltrates what it can reach

We should assume this can happen through:

- direct dependencies
- transitive dependencies
- compromised updates in reputable packages
- malicious install hooks
- malicious behavior triggered during `build`, `test`, `lint`, or `dev`

### Protected Assets

The assets `scrubs` is meant to protect are the ones that typically live on the host machine:

- `.env` files containing API keys, tokens, and credentials
- SSH keys and Git credentials
- browser cookies and authenticated sessions
- password manager data
- cloud credentials
- personal documents, notes, and unrelated source code
- access to cameras, microphones, contacts, messages, and other host-integrated data

### Trust Boundary

The core trust boundary in `scrubs` is:

- host environment: trusted for identity, personal tools, and daily computing
- sandboxed guest environment: intentionally less trusted and used for code execution

Within this model:

- the host remains the home for editors, terminal apps, browsers, and password managers
- the guest becomes the place where package installation and project execution happen
- the guest is treated as disposable infrastructure rather than as a second personal workstation

### Attacker Capabilities

If a package is compromised, we should assume attacker code can:

- execute arbitrary code as the current user inside the guest
- read files available to that user inside the guest
- inspect environment variables available to the running process
- make outbound network requests
- probe locally reachable services
- persist within the guest unless the guest is rebuilt

We should not assume the attacker already has:

- host code execution
- access to host browser sessions
- access to the host password manager
- access to unmounted host files
- access to forwarded SSH agents unless that was explicitly enabled

### Security Objective

Success means compromised dependency code can at worst access:

- the project clone inside the guest
- low-value guest-local configuration
- any secrets explicitly and temporarily placed inside the guest

It should not be able to access:

- host `.env` files unrelated to the sandboxed project
- host browser or password-manager state
- host SSH credentials
- arbitrary files from the host home directory

### Non-Goals

`scrubs` does not aim to:

- prove that a dependency is safe
- stop malicious code from running inside the guest once executed
- eliminate all risk from internet-connected development tooling
- replace careful secret hygiene within the project itself

## Design Principles

The threat model implies these principles:

- run risky dependency execution in a guest, not on the host
- clone projects inside the guest instead of bind-mounting the host checkout by default
- keep host secrets out of the guest by default
- do not forward the host SSH agent by default
- do not sign into personal browser sessions inside the guest
- do not mount the whole host home directory into the guest
- prefer per-project guest credentials over host-global credentials
- treat any secret visible to package managers and development tooling as potentially readable by compromised code

## Secret Handling Policy

The default secret policy should be:

- no personal secrets in the guest
- no automatic copying of host `.env` files into the guest
- no shared secret directories mounted from the host

If a project genuinely needs secrets for local development, prefer:

- guest-local development-only secrets with limited blast radius
- short-lived tokens
- scoped test credentials
- explicit one-time injection for a single shell or command

Avoid:

- broad host environment inheritance
- long-lived production credentials
- reusing personal credentials inside the guest

## Proposed Runtime Model

The first concrete `scrubs` runtime can use a local Linux VM as the execution boundary for risky projects.

- host stays the home for:
  - editor
  - terminal app
  - browser
  - password manager
  - personal accounts and secrets
- guest becomes the place where we run:
  - package installation
  - test suites
  - builds
  - local dev servers

The preferred workflow is:

- clone the project inside the guest
- connect from host tools into the guest over SSH or remote editing
- expose selected dev server ports back to the host browser

This is preferred over host bind-mounts because it generally improves both isolation and filesystem behavior.

## Ground Rules

- no personal browser session, password manager, or cloud credentials inside the guest
- no SSH agent forwarding by default
- do not mount the whole home directory into the guest
- treat the guest as disposable infrastructure for code execution, not as a second personal workstation
- assume rebuildability is part of normal operations

## Validation Strategy

The sandbox is only useful if it blocks realistic attacker behavior.

We should explicitly validate at least these scenarios:

- a package reads `process.env` during install and tries to exfiltrate variable names
- a package recursively searches for `.env`, `.env.*`, `.npmrc`, `.ssh`, and cloud credential files
- a package attempts to read the project parent directory and the user home directory
- a package attempts outbound HTTP exfiltration to a controlled endpoint
- a package attempts to use Git or SSH credentials available in the environment
- a package attempts to inspect forwarded local ports or guest-accessible internal services

## Red-Team Package

`scrubs` should include a small internal red-team package to simulate malicious dependency behavior.

That package should do harmless, observable versions of attacker actions:

- enumerate environment variable names
- search for interesting filenames such as `.env`, `.env.*`, `.npmrc`, `id_rsa`, and cloud credential files
- report which directories are readable
- attempt a clearly labeled outbound request to a controlled endpoint
- run from the same execution points real attacks use, such as `postinstall`, `build`, or `dev`

The package should never target real third-party endpoints and should avoid collecting secret values by default.

Instead, it should record:

- which paths were reachable
- which secret-shaped files existed
- which environment variable names were visible
- whether outbound egress worked

That gives `scrubs` a repeatable way to test whether the sandbox meaningfully reduces exposure.

## Acceptance Criteria

The sandbox is doing its job if the red-team package can successfully run inside the guest but can only observe:

- guest-local files
- guest-local environment variables
- the project clone inside the guest

And cannot observe:

- host home-directory secrets
- host browser or password-manager state
- host SSH keys or agent identities
- unrelated host files outside the intended sandbox boundary

## Initial Implementation Path

An initial implementation path for `scrubs` is:

1. choose a guest runtime and bootstrap strategy
2. create a reproducible guest configuration
3. provision language runtimes and package managers inside the guest
4. define the host-to-guest editing and terminal workflow
5. define secret injection rules
6. expose only the ports needed for local development
7. validate the boundary with the red-team package

## Open Questions

- which guest runtime should be the default for macOS hosts
- how much guest networking should be restricted by default
- whether projects should receive guest-local Git credentials automatically or manually
- how much convenience `scrubs` should trade for stronger isolation
- how to make guest rebuilds fast enough to be routine
