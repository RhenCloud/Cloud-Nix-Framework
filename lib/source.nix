{ lib }:

let
  defaultExcludes = [
    ".git"
    ".direnv"
    ".cnh"
    "result"
  ];

  normalize = value: lib.removePrefix "./" (lib.removeSuffix "/" value);
in
{
  clean =
    {
      root,
      excludes ? [ ],
      name ? "cloud-project-source",
    }:
    let
      rootString = toString root;
      excluded = map normalize (defaultExcludes ++ excludes);
      isExcluded =
        relative: lib.any (item: relative == item || lib.hasPrefix "${item}/" relative) excluded;
    in
    builtins.path {
      path = root;
      inherit name;
      filter =
        path: _:
        let
          pathString = toString path;
          relative = lib.removePrefix "${rootString}/" pathString;
        in
        pathString == rootString || !isExcluded relative;
    };

  inherit defaultExcludes;
}
