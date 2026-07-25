# tdarr-setup Job (media)

Post-install/upgrade hook (`helm.sh/hook-weight: 35`) that bootstraps Tdarr from
values so library monitoring/transcode policy is reproducible.

It upserts:

1. A flow (`inputFile` -> `runClassicTranscodePlugin` -> `replaceOriginalFile`)
2. A library bound to that flow, pointing at the configured folder
3. Folder-watch status (+ optional `scanFindNew` trigger)

Driven by `tdarr.setup.*` in `values/default/media/tdarr.yaml`.
