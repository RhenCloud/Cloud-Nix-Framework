{ runCommand }:
runCommand "snowveil-example-check" { } ''
  touch "$out"
''
