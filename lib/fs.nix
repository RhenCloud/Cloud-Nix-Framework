{ lib }:

let
  listDir =
    dir:
    let
      entries = builtins.readDir dir;
    in
    map (name: {
      inherit name;
      type = entries.${name};
    }) (builtins.attrNames entries);

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
    tree:
    let
      go =
        prefix: value:
        lib.concatMap (
          name:
          let
            item = value.${name};
            key = if prefix == "" then name else "${prefix}.${name}";
          in
          if builtins.isAttrs item then go key item else [ (lib.nameValuePair key item) ]
        ) (builtins.attrNames value);
    in
    builtins.listToAttrs (go "" tree);

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
        index = { };
      }
    else
      let
        magic = [
          "options.nix"
          "default.nix"
          "nixos.nix"
          "home.nix"
        ];
        sharedMagic = [
          "options.nix"
          "default.nix"
        ];
        sideMagic = {
          nixos = sharedMagic ++ [ "nixos.nix" ];
          home = sharedMagic ++ [ "home.nix" ];
        };
        magicSet = lib.genAttrs magic (_: true);
        relevant = lib.filter (file: builtins.hasAttr file.base magicSet) (walk dir);
        folderOf = file: lib.removeSuffix ("/" + file.base) file.rel;
        nameOf = folder: lib.replaceStrings [ "/" ] [ "." ] folder;
        folderRecords =
          map
            (folder: {
              inherit folder;
              name = nameOf folder;
            })
            (
              builtins.attrNames (
                builtins.listToAttrs (map (file: lib.nameValuePair (folderOf file) true) relevant)
              )
            );
        foldersByName = lib.groupBy (record: record.name) folderRecords;
        collisions = lib.filterAttrs (_: records: builtins.length records > 1) foldersByName;
        collisionDetails = lib.concatMapStringsSep "\n" (
          name:
          let
            paths = map (record: dir + "/" + record.folder) collisions.${name};
          in
          "  - '${name}': ${lib.concatStringsSep ", " paths}"
        ) (builtins.attrNames collisions);
        checkedFolders =
          if collisions != { } then
            throw ''
              error: module discovery detected name collisions

              the following module names are defined in multiple directories:
              ${collisionDetails}

              hint: rename directories to ensure each module has a unique name
            ''
          else
            folderRecords;
        fileIndex = builtins.listToAttrs (map (file: lib.nameValuePair file.rel file.path) relevant);
        pathFor =
          folder: base:
          let
            relative = if folder == "" then base else "${folder}/${base}";
          in
          fileIndex.${relative} or null;
        pathsFor =
          side: folder: lib.filter (path: path != null) (map (base: pathFor folder base) sideMagic.${side});
        group =
          side:
          builtins.listToAttrs (
            lib.concatMap (
              record:
              let
                paths = pathsFor side record.folder;
              in
              lib.optional (paths != [ ]) (lib.nameValuePair record.name paths)
            ) checkedFolders
          );
        meta = builtins.listToAttrs (
          map (
            record:
            let
              path = dir + "/" + record.folder + "/meta.nix";
            in
            lib.nameValuePair record.name {
              inherit path;
              value = readMetadata path;
            }
          ) checkedFolders
        );
        nixos = group "nixos";
        home = group "home";
        index = builtins.listToAttrs (
          map (
            record:
            lib.nameValuePair record.name {
              inherit (record) folder name;
              role = lib.head (lib.splitString "/" record.folder);
              common = lib.hasPrefix "_" record.folder;
              shared = lib.filter (path: path != null) (map (base: pathFor record.folder base) sharedMagic);
              nixosOnly =
                let
                  p = pathFor record.folder "nixos.nix";
                in
                lib.optional (p != null) p;
              homeOnly =
                let
                  p = pathFor record.folder "home.nix";
                in
                lib.optional (p != null) p;
              nixos = nixos.${record.name} or [ ];
              home = home.${record.name} or [ ];
              meta = meta.${record.name};
            }
          ) checkedFolders
        );
      in
      {
        inherit
          nixos
          home
          meta
          index
          ;
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
