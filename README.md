# nouritsu's F-Droid repo

The F-Droid repo at [fdroid.nouritsu.com](https://fdroid.nouritsu.com): the signed releases of these apps, as one repo with one address and fingerprint.

| App | Source |
| --- | --- |
| Fast Track, an intermittent fasting tracker | [nouritsu/fast-track](https://github.com/nouritsu/fast-track) |
| Karteikasten, flashcards for the 2,000 most common German words | [nouritsu/karteikasten](https://github.com/nouritsu/karteikasten) |

## Adding it

Open [fdroid.nouritsu.com](https://fdroid.nouritsu.com) on your phone and tap **Add to F-Droid**, or scan its QR code. By hand, in F-Droid, Droid-ify or Neo Store:

- Address: `https://fdroid.nouritsu.com/repo`
- Fingerprint: `1C7F39DD34C841BE845D3B47EF5A5FB3CBDB9A28748D8862183AB0FEC867E971`

## How it is built

Nothing is built from source here: each app builds, signs and attests its own APKs in its release workflow, then sends this repository a `repository_dispatch` event. [publish.yml](.github/workflows/publish.yml) then:

1. downloads the newest version releases of every app in [apps.json](apps.json), checking each APK against its release's `SHA256SUMS`;
2. takes each app's store texts and screenshots from its `fastlane/metadata/android/` at its newest release;
3. runs `fdroid update` (`nix run .#fdroid-repo`), which signs the index with the repo key;
4. uploads the site to the server with rsync, through a deploy key confined to the repo's folder.

It also runs by hand (Actions → Publish → Run workflow).

### Secrets

| Secret | What |
| --- | --- |
| `FDROID_KEYSTORE_BASE64`, `FDROID_KEYSTORE_PASSWORD`, `FDROID_KEY_ALIAS`, `FDROID_KEY_PASSWORD` | The repo's signing key, which the fingerprint above belongs to |
| `FDROID_SSH_KEY`, `FDROID_SSH_KNOWN_HOSTS` | The deploy key for `fdroid-deployer@nouritsu.com`, and the server's pinned host key |

Each app's repository holds an `FDROID_DISPATCH_TOKEN`: a fine-grained token for this repository alone, with Contents: read and write, the least that may send it a `repository_dispatch` event.

### Adding an app

Add it to [apps.json](apps.json) and its entry to [fdroid/metadata/](fdroid/metadata/), then have its release workflow send the event, as Karteikasten's does.

## Licence

[GPL-3.0-or-later](LICENSE).
