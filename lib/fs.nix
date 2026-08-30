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
        # Load order: options.nix → default.nix → specialized nix
        # options.nix is always injected (interface declaration)
        # default.nix is neutral implementation (both sides use)
        # nixos.nix / home.nix are specialized implementations
        magic = [
          "options.nix"
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
            dups = lib.unique (lib.filter (name: lib.count (x: x == name) names > 1) names);
            dupDetails = lib.concatMapStringsSep "\n" (
              dupName:
              let
                dupFolders = lib.filter (folder: nameOf folder == dupName) folders;
                paths = lib.concatMapStringsSep ", " (folder: dir + "/" + folder) dupFolders;
              in
              "  - '${dupName}': ${paths}"
            ) dups;
          in
          if dups != [ ] then
            throw ''
              error: module discovery detected name collisions

              the following module names are defined in multiple directories:
              ${dupDetails}

              hint: rename directories to ensure each module has a unique name
            ''
          else
            lib.listToAttrs (
              map (
                folder:
                let
                  # Collect all matching files in this folder, preserving load order
                  filesInFolder = lib.filter (f: folderOf f == folder) matched;
                in
                lib.nameValuePair (nameOf folder) (map (f: f.path) filesInFolder)
              ) folders
            );
      in
      {
        # NixOS side: options.nix + default.nix + nixos.nix
        nixos = group (b: b == "options.nix" || b == "default.nix" || b == "nixos.nix");
        # home-manager side: options.nix + default.nix + home.nix
        home = group (b: b == "options.nix" || b == "default.nix" || b == "home.nix");
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
