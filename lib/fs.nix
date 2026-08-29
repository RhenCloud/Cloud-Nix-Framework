{
  lib,
}:

let
  listDir =
    dir:
    lib.sort (a: b: a.name < b.name) (
      lib.mapAttrsToList (name: type: {
        inherit name type;
      }) (builtins.readDir dir)
    );

  walk =
    dir:
    let
      go =
        prefix: current:
        lib.concatMap (
          entry:
          let
            path = current + "/${entry.name}";
            relative = if prefix == "" then entry.name else prefix + "/${entry.name}";
          in
          if entry.type == "directory" then
            go relative path
          else
            [
              {
                rel = relative;
                inherit path;
                base = entry.name;
              }
            ]
        ) (listDir current);
    in
    lib.sort (a: b: a.rel < b.rel) (go "" dir);

  flattenTree =
    let
      go =
        prefix: tree:
        lib.foldlAttrs (
          acc: name: value:
          let
            key = if prefix == "" then name else prefix + "." + name;
          in
          if builtins.isAttrs value then acc // go key value else acc // { ${key} = value; }
        ) { } tree;
    in
    go "";

  groupModules =
    dir:
    if !builtins.pathExists dir then
      {
        nixos = [ ];
        home = [ ];
      }
    else
      let
        magic = [
          "default.nix"
          "nixos.nix"
          "home.nix"
        ];
        relevant = lib.filter (f: builtins.elem f.base magic) (walk dir);
        folderOf = f: lib.removeSuffix ("/" + f.base) f.rel;
        nameOf = folder: lib.strings.replaceStrings [ "/" ] [ "." ] folder;
        group =
          pred:
          let
            matched = lib.filter (f: pred f.base) relevant;
            folders = lib.unique (map folderOf matched);
            names = map nameOf folders;
            dups = lib.subtractLists (lib.unique names) names;
          in
          if dups != [ ] then
            throw "modules 下发现重名模块目录：${lib.concatStringsSep ", " dups}（不同路径映射到同一模块名，请重命名以避免冲突）"
          else
            lib.listToAttrs (
              map (
                folder:
                lib.nameValuePair (nameOf folder) (map (f: f.path) (lib.filter (f: folderOf f == folder) matched))
              ) folders
            );
      in
      {
        nixos = group (b: b == "default.nix" || b == "nixos.nix");
        home = group (b: b == "default.nix" || b == "home.nix");
      };

  importModules =
    dir:
    let
      grouped = groupModules dir;
    in
    {
      nixos = lib.concatLists (lib.attrValues grouped.nixos);
      home = lib.concatLists (lib.attrValues grouped.home);
    };
in
{
  inherit listDir;
  inherit walk;
  inherit flattenTree;
  inherit importModules;
  inherit groupModules;
}
