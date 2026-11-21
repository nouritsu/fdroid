# `nix run .#fdroid-repo -- --apks DIR --metadata DIR --keystore PATH --alias NAME`: builds
# the F-Droid repo for fdroid.nouritsu.com from the signed APKs in --apks, for every app in
# apps.json, with each app's store texts and screenshots from --metadata/<app id>/ (its
# fastlane/metadata/android/), and writes the site to out/fdroid/: a front page, repo/
# and archive/, ready to rsync. The repo key's passwords come from
# FDROID_REPO_KEYSTORE_PASS and FDROID_REPO_KEY_PASS.
# Each version is dated by its APK file's mtime (--use-date-from-apk), so the same
# releases make the same index on every run.
{
  lib,
  runCommand,
  writers,
  coreutils,
  fdroidserver,
  git,
  jdk21,
  jq,
  vips,
}: let
  # The repo's own icon in the clients; each app's icon comes from its APK.
  icon = runCommand "fdroid-repo-icon" {nativeBuildInputs = [vips];} ''
    mkdir $out
    vips thumbnail ${../icon.svg} "$out/icon.png[strip]" 512
  '';
  config = ../fdroid;
  apps = ../apps.json;
in
  writers.writeFishBin "fdroid-repo" ''
    argparse 'apks=' 'metadata=' 'keystore=' 'alias=' -- $argv; or exit 2
    set -gx PATH ${lib.makeBinPath [coreutils fdroidserver git jdk21 jq]} $PATH

    set -l root (git rev-parse --show-toplevel 2>/dev/null)
    if not test -f "$root/flake.nix"
        echo "fdroid-repo: run this inside the repository" >&2
        exit 1
    end
    for flag in apks metadata keystore alias
        if not set -q _flag_$flag
            echo "fdroid-repo: usage: --apks DIR --metadata DIR --keystore PATH --alias NAME" >&2
            exit 2
        end
    end
    if not test -f $_flag_keystore
        echo "fdroid-repo: no keystore at $_flag_keystore" >&2
        exit 1
    end
    for var in FDROID_REPO_KEYSTORE_PASS FDROID_REPO_KEY_PASS
        if test -z "$$var"
            echo "fdroid-repo: set $var" >&2
            exit 1
        end
    end
    set -l apks $_flag_apks/*.apk
    if test (count $apks) -eq 0
        echo "fdroid-repo: no APKs in $_flag_apks" >&2
        exit 1
    end

    # config.yml reads these with fdroidserver's {env: NAME}.
    set -gx FDROID_REPO_KEYSTORE (path resolve $_flag_keystore)
    set -gx FDROID_REPO_KEY_ALIAS $_flag_alias

    set -g work (mktemp -d)
    function cleanup --on-event fish_exit
        rm -rf $work
    end

    # fdroidserver warns about a config naming passwords that others can read.
    install -m 600 ${config}/config.yml $work/config.yml
    mkdir -p $work/metadata $work/repo/icons $work/archive/icons
    # Each app: its entry, and its store texts and screenshots, which fdroid update reads
    # from metadata/<app id>/<locale>/ in a binary-only repo:
    # https://f-droid.org/docs/All_About_Descriptions_Graphics_and_Screenshots/
    for id in (jq -r '.[].id' ${apps})
        cp --no-preserve=mode ${config}/metadata/$id.yml $work/metadata/
        if test -d $_flag_metadata/$id
            cp -r --no-preserve=mode $_flag_metadata/$id $work/metadata/$id
        else
            echo "fdroid-repo: no store texts for $id in $_flag_metadata; its entry will be bare" >&2
        end
    end
    cp --preserve=timestamps $apks $work/repo/
    for dir in repo archive
        cp --no-preserve=mode ${icon}/icon.png $work/$dir/icons/
    end

    cd $work; or exit 1
    fdroid update --use-date-from-apk; or exit 1

    # fdroid update skips an APK it can't read or verify; stop rather than drop a version.
    set -l indexed (jq -s 'map(.packages // {} | map(.versions | length) | add // 0) | add' repo/index-v2.json archive/index-v2.json)
    if test "$indexed" -ne (count $apks)
        echo "fdroid-repo: indexed $indexed of "(count $apks)" APKs; see fdroid update's warnings" >&2
        exit 1
    end

    # The fingerprint clients check: the SHA-256 of the signing certificate.
    keytool -exportcert -keystore $FDROID_REPO_KEYSTORE -alias $_flag_alias \
        -storepass:env FDROID_REPO_KEYSTORE_PASS >$work/cert.der; or exit 1
    set -l fingerprint (sha256sum $work/cert.der | string split -f1 ' ' | string upper)
    set -l repo_url (jq -r .repo.address repo/index-v1.json)
    set -l add_url "fdroidrepos://"(string replace -r '^https://' "" $repo_url)"?fingerprint=$fingerprint"

    # The front page lists the apps from apps.json, in its order.
    set -l list (jq -r '.[] | "      <li><a href=\"https://github.com/\(.repo)\">\(.name)</a>, \(.about)</li>"' ${apps} | string collect)

    set -l site $root/out/fdroid
    rm -rf $site
    mkdir -p $site
    cp -r repo archive $site/
    string replace -a @REPO_URL@ $repo_url <${config}/index.html \
        | string replace -a @ADD_URL@ $add_url \
        | string replace -a @APPS@ $list \
        | string replace -a @FINGERPRINT@ (string replace -ra '(..)(?=.)' '$1 ' $fingerprint) >$site/index.html

    echo "$site: $indexed versions"
    echo "Fingerprint: $fingerprint"
    echo "Add: $add_url"
  ''
