# iStore application diagnostics

`istoreos-app-diagnostics` diagnoses the most recent iStore installation without changing iStore or taskd. It is a manual helper reached from `kai-software`, so its instructions and app index do not occupy every-turn context.

## Runtime contract

- `inspect.sh latest` diagnoses the app found in the current `istore` task.
- `inspect.sh <app-id>` uses the task log only when the task package exactly matches.
- `inspect.sh <app-id> --detail package|autoconf|runtime` returns one filtered, sanitized phase excerpt.
- The Store endpoint is the complete aggregated inventory. The 65-entry app-hub index is only first-party source knowledge; neither overrides device package/files/service state.
- The fixed task id and log are ephemeral. If taskd has collected them, the report returns `NO_RECENT_TASK`; historical recovery is intentionally not claimed.
- Reports never trigger install, retry, configuration, service restart, or container changes.

## Release checks

From the `linkease-skills` repository:

```sh
ISTOREOS_APP_HUB_ROOT=/path/to/istoreos-app-hub \
  sh istoreos/tests/test_app_diagnostics_release.sh
```

From the app hub repository, regenerate and verify the source-derived index:

```sh
make apps-catalog
make apps-diagnostics-check
```

Live model checks are intentionally separate from offline CI and require credentials:

```sh
DEEPSEEK_CREDENTIALS_FILE=/path/to/credentials \
  sh istoreos/tests/test_live_app_diagnostics_reasoning.sh
```
