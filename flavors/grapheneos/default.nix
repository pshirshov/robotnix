# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:
let
  inherit (lib)
    optional optionalString optionalAttrs elem
    mkIf mkMerge mkDefault mkForce;

  upstreamParams = import ./upstream-params.nix;
  grapheneOSRelease = "${config.apv.buildID}.${upstreamParams.buildNumber}";

  phoneDeviceFamilies = [ "crosshatch" "bonito" "coral" "sunfish" "redfin" "barbet" ];
  supportedDeviceFamilies = phoneDeviceFamilies ++ [ "generic" ];

in mkIf (config.flavor == "grapheneos") (mkMerge [
{
  buildNumber = mkDefault upstreamParams.buildNumber;
  buildDateTime = mkDefault upstreamParams.buildDateTime;

  productNamePrefix = mkDefault "";

  # Match upstream user/hostname
  envVars = {
    BUILD_USERNAME = "grapheneos";
    BUILD_HOSTNAME = "grapheneos";
  };

  source.dirs = lib.importJSON (./. + "/repo-${grapheneOSRelease}.json");

  apv.enable = mkIf (elem config.deviceFamily phoneDeviceFamilies) (mkDefault true);
  apv.buildID = mkMerge [
    (mkIf (config.device != "barbet") (mkDefault "RQ3A.210905.001"))
    (mkIf (config.device == "barbet") (mkDefault "RD2A.210905.003"))
  ];

  # Not strictly necessary for me to set these, since I override the source.dirs above
  source.manifest.url = mkDefault "https://github.com/GrapheneOS/platform_manifest.git";
  source.manifest.rev = mkDefault "refs/tags/${grapheneOSRelease}";

  warnings = (optional ((config.device != null) && !(elem config.deviceFamily supportedDeviceFamilies))
    "${config.device} is not a supported device for GrapheneOS")
    ++ (optional (config.androidVersion != 11) "Unsupported androidVersion (!= 11) for GrapheneOS");
}
{
  # Disable setting SCHED_BATCH in soong. Brings in a new dependency and the nix-daemon could do that anyway.
  source.dirs."build/soong".patches = [
    (pkgs.fetchpatch {
      url = "https://github.com/GrapheneOS/platform_build_soong/commit/76723b5745f08e88efa99295fbb53ed60e80af92.patch";
      sha256 = "0vvairss3h3f9ybfgxihp5i8yk0rsnyhpvkm473g6dc49lv90ggq";
      revert = true;
    })
  ];

  # No need to include kernel sources in Android source trees since we build separately
  source.dirs."kernel/google/marlin".enable = false;
  source.dirs."kernel/google/wahoo".enable = false;
  source.dirs."kernel/google/crosshatch".enable = false;
  source.dirs."kernel/google/bonito".enable = false;
  source.dirs."kernel/google/coral".enable = false;
  source.dirs."kernel/google/sunfish".enable = false;
  source.dirs."kernel/google/redbull".enable = false;
  source.dirs."kernel/google/barbet".enable = false;

  # Enable Vanadium (GraphaneOS's chromium fork).
  apps.vanadium.enable = mkDefault true;
  webview.vanadium.enable = mkDefault true;
  webview.vanadium.availableByDefault = mkDefault true;

  apps.seedvault.includedInFlavor = mkDefault true;
  apps.updater.includedInFlavor = mkDefault true;

  # Remove upstream prebuilt versions from build. We build from source ourselves.
  removedProductPackages = [ "TrichromeWebView" "TrichromeChrome" "webview" ];
  source.dirs."external/vanadium".enable = false;

  # Override included android-prepare-vendor, with the exact version from
  # GrapheneOS. Unfortunately, Doing it this way means we don't cache apv
  # output across vanilla/grapheneos, even if they are otherwise identical.
  source.dirs."vendor/android-prepare-vendor".enable = false;
  nixpkgs.overlays = [ (self: super: {
    android-prepare-vendor = super.android-prepare-vendor.overrideAttrs (_: {
      src = config.source.dirs."vendor/android-prepare-vendor".src;
      passthru.evalTimeSrc = builtins.fetchTarball {
        url = "https://github.com/GrapheneOS/android-prepare-vendor/archive/${config.source.dirs."vendor/android-prepare-vendor".rev}.tar.gz";
        inherit (config.source.dirs."vendor/android-prepare-vendor") sha256;
      };
    });
  }) ];

  # GrapheneOS just disables apex updating wholesale
  signing.apex.enable = false;

  # Extra packages that should use releasekey
  signing.signTargetFilesArgs = [ "--extra_apks OsuLogin.apk,ServiceWifiResources.apk=$KEYSDIR/${config.device}/releasekey" ];

  # Leave the existing auditor in the build--just in case the user wants to
  # audit devices using the official upstream build
}
(mkIf (elem config.deviceFamily phoneDeviceFamilies) {
  kernel.enable = mkDefault true;
  kernel.src = mkDefault config.source.dirs."kernel/google/${config.kernel.name}".src;
  kernel.configName = config.device;
  kernel.relpath = "device/google/${config.device}-kernel";
})
{
  # Hackish exceptions
  kernel.src = mkIf (config.deviceFamily == "bonito") (mkForce config.source.dirs."kernel/google/crosshatch".src);
  kernel.configName = mkMerge [
    (mkIf (config.device       == "sargo" ) (mkForce "bonito" ))
    (mkIf (config.deviceFamily == "coral" ) (mkForce "floral" ))
    (mkIf (config.device       == "barbet") (mkForce "bramble"))
  ];
  kernel.relpath = mkMerge [
    (mkIf (config.device == "sargo") (mkForce "device/google/bonito-kernel"))
  ];
}
])
