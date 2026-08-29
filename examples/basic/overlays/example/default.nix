{
  cloud,
}:
final: prev: {
  cloud-example = prev.runCommand "cloud-example" { } ''
    echo "overlay-ok" > "$out"
  '';
  cloud-common = toString cloud.sops.commonFile;
}
