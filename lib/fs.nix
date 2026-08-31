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

  readMetadata =
    path:
    if !builtins.pathExists path then
      { }
    else
      let
        value = import path;
      in
      if builtins.isAttrs value && !builtins.isFunction value then
        value
      else
        throw "元数据文件 '${toString path}' 必须直接返回属性集";

  groupModules =
    dir:
    if !builtins.pathExists dir then
      {
        nixos = { };
        home = { };
        meta = { };
      }
    else
      let
        magic = [
          "options.nix"
          "default.nix"
          "nixos.nix"
          "home.nix"
        ];
        relevant = lib.filter (f: builtins.elem f.base magic) (walk dir);
        folderOf = f: lib.removeSuffix ("/" + f.base) f.rel;
        nameOf = folder: lib.strings.replaceStrings [ "/" ] [ "." ] folder;
        folders = lib.unique (map folderOf relevant);
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
        checkedFolders =
          if dups != [ ] then
            throw ''
              error: module discovery detected name collisions

              the following module names are defined in multiple directories:
              ${dupDetails}

              hint: rename directories to ensure each module has a unique name
            ''
          else
            folders;
        group =
          pred:
          lib.listToAttrs (
            map (
              folder:
              let
                filesInFolder = lib.concatMap (
                  base: lib.filter (f: folderOf f == folder && f.base == base && pred base) relevant
                ) magic;
              in
              lib.nameValuePair (nameOf folder) (map (f: f.path) filesInFolder)
            ) (lib.filter (folder: lib.any (f: folderOf f == folder && pred f.base) relevant) checkedFolders)
          );
        meta = lib.listToAttrs (
          map (
            folder:
            let
              path = dir + "/" + folder + "/meta.nix";
            in
            lib.nameValuePair (nameOf folder) {
              inherit path;
              value = readMetadata path;
            }
          ) checkedFolders
        );
      in
      {
        nixos = group (b: b == "options.nix" || b == "default.nix" || b == "nixos.nix");
        home = group (b: b == "options.nix" || b == "default.nix" || b == "home.nix");
        inherit meta;
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
  inherit
    listDir
    walk
    flattenTree
    importModules
    groupModules
    ;
}
