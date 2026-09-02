{
  snowveil,
  self,
  ...
}:
final: prev: {
  snowveil-example = prev.runCommand "snowveil-example" { } ''
    echo "overlay-ok" > "$out"
  '';
  snowveil-common = toString snowveil.sops.commonFile;
  snowveil-self = toString self.outPath;
}
