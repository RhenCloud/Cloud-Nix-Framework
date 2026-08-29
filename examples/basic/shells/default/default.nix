{
  mkShell,
  hello,
}:
mkShell {
  packages = [ hello ];
}
