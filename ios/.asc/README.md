# App Store Connect API key drop-box

This folder holds your personal App Store Connect API key so
`ios/scripts/release.sh` can sign and upload builds non-interactively.
**Everything in this folder except this README is gitignored** — nothing
here is ever committed.

## 1. Generate the key (Will-checkpoint W1)

In App Store Connect: **Users and Access → Integrations → App Store
Connect API → Team Keys → Generate API Key**.

- Role: **App Manager**.
- Download the `.p8` file immediately — App Store Connect only lets you
  download it once.

## 2. Drop it here

1. Place the downloaded file at `ios/.asc/AuthKey_<KEYID>.p8`, keeping
   Apple's filename (`<KEYID>` is the Key ID shown next to the key on the
   same page).
2. Create `ios/.asc/config.env` beside it with:

   ```
   ASC_KEY_ID=<KEYID>
   ASC_ISSUER_ID=<issuer UUID from the same page>
   ```

That's it. `ios/scripts/release.sh` sources `config.env` to read
`ASC_KEY_ID` and `ASC_ISSUER_ID`, then finds the key at
`ios/.asc/AuthKey_${ASC_KEY_ID}.p8`. If either file is missing, `archive`,
`export`, and `upload` all fail fast and point back at this file instead of
running.
