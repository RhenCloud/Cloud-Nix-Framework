extras: final: prev: {
  snowveil-example = prev.runCommand "snowveil-example" { } ''
    echo "overlay-ok" > "$out"
  '';
  snowveil-common = toString extras.snowveil.sops.commonFile;
  snowveil-self = toString extras.self.outPath;
}
