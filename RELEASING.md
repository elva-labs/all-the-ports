# Releasing

Releases are built, signed, notarized, and published by CI when a version tag
is pushed:

```sh
git tag v1.0.0
git push origin v1.0.0
```

The workflow (`.github/workflows/release.yml`) produces a Gatekeeper-clean
`all-the-ports-<version>.zip` on the GitHub release.

## One-time setup

Five repository secrets are required. All values come from the Apple
Developer account (Elva Group AB, team WL4K563SDJ).

### 1. Signing certificate (.p12)

The "Developer ID Application" certificate + private key live in the login
keychain of the Mac that generated the CSR. To export:

1. Keychain Access → login → My Certificates
2. Right-click "Developer ID Application: Elva Group AB (WL4K563SDJ)"
   → Export… → file format ".p12" → choose a strong password.
3. Store the .p12 and its password in a password manager — the private key
   cannot be re-downloaded from Apple, and losing it burns one of the
   account's five Developer ID certificate slots.

### 2. Notarization API key (.p8)

1. https://appstoreconnect.apple.com → Users and Access → Integrations
   → App Store Connect API → Team Keys → Generate API Key
2. Role: **Developer** is sufficient.
3. Download the `.p8` (downloadable only once) and note the **Key ID** and
   the page's **Issuer ID**.

### 3. Add the secrets

From a terminal in this repo:

```sh
base64 -i DeveloperID.p12 | gh secret set MACOS_CERT_P12
gh secret set MACOS_CERT_PASSWORD        # paste the .p12 password
gh secret set APPLE_API_KEY_P8 < AuthKey_XXXXXXXXXX.p8
gh secret set APPLE_API_KEY_ID           # paste the Key ID
gh secret set APPLE_API_ISSUER_ID        # paste the Issuer ID
```

Then delete any exported key material from disk.

## Local signed builds (optional)

```sh
SIGN_IDENTITY="Developer ID Application: Elva Group AB (WL4K563SDJ)" scripts/make-app.sh
```

Plain `make app` stays ad-hoc signed — fine locally, not distributable.
