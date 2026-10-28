---
name: target-ssh-controller
description: Bind a specific remote target over SSH and safely execute target scripts with strict host-key verification, bounded timeouts, explicit write approval, and no operating-system business logic.
owner: transport/ssh
systems: any
requires: ssh-client
---

# SSH Target Controller

Use this skill only when the current Agent has no built-in target runtime and must reach a bound target through SSH. System diagnosis and repair belong to the selected system skill; this controller only transports its script to the target shell.

## Binding contract

Set `TARGET_ID`, `TARGET_SSH_HOST`, `TARGET_SSH_USER`, and `TARGET_SSH_KNOWN_HOSTS` for every call. Optional values are `TARGET_SSH_PORT`, `TARGET_SSH_IDENTITY`, and `TARGET_TIMEOUT_SECONDS`. Credentials stay in an SSH agent or protected key file and never enter prompts, logs, or this repository.

Unknown or changed host keys are a hard stop. Never add `StrictHostKeyChecking=no`, discard known-host state, or accept a changed fingerprint without out-of-band user verification.

## Execution contract

Pipe a complete POSIX shell program to the runner and declare its phase:

```sh
sh scripts/target-ssh.sh inspect < inspect.sh
sh scripts/target-ssh.sh plan < plan.sh
TARGET_CHANGE_APPROVED=YES sh scripts/target-ssh.sh apply < apply.sh
sh scripts/target-ssh.sh verify < verify.sh
```

`inspect`, `plan`, and `verify` must be read-only. `apply` is rejected without explicit approval. Scripts execute through the bound remote shell via stdin, so controller-host paths and commands are never treated as target state. Prefer scripts that emit bounded structured output and clean any target-side temporary assets with a trap.

Use `facts` for the controller's fixed, read-only target capability probe:

```sh
sh scripts/target-ssh.sh facts
```

The runner provides `target.exec`, `target.run-script`, and `target.facts`. Timeouts and cancellation errors are transport failures; they are not evidence about the target operating system.
