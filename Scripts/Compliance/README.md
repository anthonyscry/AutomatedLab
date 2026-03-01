# Compliance control map

## Schema

- `Checks` (hashtable): key is a check identifier (for example `DNS.ExternalResolution`).
  - `Title`: human-friendly name.
  - `Description`: what the check tracks.
  - `FrameworkMappings`: ordered array of mappings describing how this check aligns with frameworks.
    - `Framework`: framework name.
    - `ControlId`: identifier within that framework (for example `SC-8`).

## Adding a check

1. Add a new entry under `Checks` inside `ControlMap.psd1` using the check id as the key.
2. Give the entry a `Title`, `Description`, and at least one `FrameworkMappings` entry.
3. Save and rely on the helpers in `Scripts/Helpers-ComplianceReport.ps1` to expose the data.
