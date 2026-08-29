extras: final: prev: {
  cloud-example = prev.runCommand "cloud-example" { } ''
    echo "overlay-ok" > "$out"
  '';
  cloud-common = toString extras.cloud.sops.commonFile;
  cloud-self = toString extras.self.outPath;
}
