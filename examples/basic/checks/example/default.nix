{ runCommand }:
runCommand "cloud-example-check" { } ''
  touch "$out"
''
