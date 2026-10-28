---
name: target-ssh-powershell-controller
description: Bind a target through OpenSSH and execute PowerShell scripts with strict host-key checking, bounded timeouts, target identity, and explicit apply approval.
owner: transport/ssh
systems: any
requires: ssh-client
---

# SSH PowerShell target controller

Use this only for a target that exposes PowerShell through OpenSSH. System-specific diagnosis and changes remain in the selected System Pack.

Set `TARGET_ID`, `TARGET_SSH_HOST`, `TARGET_SSH_USER`, and `TARGET_SSH_KNOWN_HOSTS`; optionally set port, identity, and timeout. Credentials stay in an SSH agent or protected key file. Unknown or changed host keys are a hard stop.

```sh
sh scripts/target-ssh-powershell.sh inspect < inspect.ps1
sh scripts/target-ssh-powershell.sh plan < plan.ps1
TARGET_CHANGE_APPROVED=YES sh scripts/target-ssh-powershell.sh apply < apply.ps1
sh scripts/target-ssh-powershell.sh verify < verify.ps1
```

The script is sent over stdin and executes only on the bound target. `apply` requires fresh user approval. Timeout, cancellation, authentication, and shell startup failures are transport errors, not operating-system conclusions.

The controller needs `iconv`, `base64`, `awk`, and `mktemp`. It sends UTF-8 scripts over stdin, uses a temporary BOM script on the target, and removes it after execution. A per-call status frame preserves the child exit code when the SSH default PowerShell would normalize it. This does not change the target default shell or persistent execution policy.

`TARGET_TIMEOUT_SECONDS` bounds the remote child execution. A Windows job owns
the child and its descendants, killing them on timeout or supervisor termination;
detached background services are therefore outside this Transport's lifecycle.
The controller allows 15 additional seconds for SSH setup and remote cleanup.
Timeout returns 124. A supervision or status-frame failure returns 255.
