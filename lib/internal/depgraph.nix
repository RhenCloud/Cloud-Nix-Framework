{ lib }:

let
  sortNames = lib.sort (a: b: a < b);

  dropUntil =
    target: values:
    if values == [ ] || lib.head values == target then values else dropUntil target (lib.tail values);

  readStringList =
    {
      field,
      metaPath,
      value,
    }:
    if builtins.isList value && lib.all (item: builtins.isString item && item != "") value then
      lib.unique value
    else
      throw ''
        error: 模块依赖元数据无效

        ${toString metaPath} 中的 '${field}' 必须是非空字符串组成的列表
        当前类型：${builtins.typeOf value}
      '';

  readGroupMembers =
    {
      name,
      value,
      side,
    }:
    if name == "" then
      throw "moduleGroups 的名称必须是非空字符串"
    else if builtins.isList value then
      let
        members = readStringList {
          field = "moduleGroups.${name}";
          metaPath = "mkFlake";
          inherit value;
        };
      in
      if members == [ ] then throw "moduleGroups.${name} 不能为空" else members
    else if builtins.isAttrs value then
      let
        supportedFields = [
          "common"
          "nixos"
          "home"
        ];
        unknownFields = lib.filter (field: !builtins.elem field supportedFields) (builtins.attrNames value);
        common = readStringList {
          field = "moduleGroups.${name}.common";
          metaPath = "mkFlake";
          value = value.common or [ ];
        };
        nixos = readStringList {
          field = "moduleGroups.${name}.nixos";
          metaPath = "mkFlake";
          value = value.nixos or [ ];
        };
        home = readStringList {
          field = "moduleGroups.${name}.home";
          metaPath = "mkFlake";
          value = value.home or [ ];
        };
        allMembers = lib.unique (common ++ nixos ++ home);
        sideMembers = if side == "nixos" then nixos else home;
      in
      if unknownFields != [ ] then
        throw "moduleGroups.${name} 包含不支持的字段：${lib.concatStringsSep ", " unknownFields}"
      else if allMembers == [ ] then
        throw "moduleGroups.${name} 不能为空"
      else
        lib.unique (common ++ sideMembers)
    else
      throw ''
        error: 模块组定义无效

        moduleGroups.${name} 必须是字符串列表或包含 common/nixos/home 的属性集
      '';

  topologicalOrder =
    {
      nodes,
      enabled,
      side,
    }:
    let
      findCycle =
        remaining:
        let
          follow =
            current: path:
            if builtins.elem current path then
              (dropUntil current path) ++ [ current ]
            else
              let
                candidates = sortNames (
                  lib.filter (name: builtins.elem name remaining) nodes.${current}.orderAfter
                );
              in
              follow (lib.head candidates) (path ++ [ current ]);
        in
        follow (lib.head (sortNames remaining)) [ ];

      go =
        remaining: result:
        if remaining == [ ] then
          result
        else
          let
            ready = sortNames (
              lib.filter (
                name: lib.all (dependency: !builtins.elem dependency remaining) nodes.${name}.orderAfter
              ) remaining
            );
          in
          if ready == [ ] then
            let
              cycle = findCycle remaining;
            in
            throw ''
              error: 检测到模块循环依赖（${side} 侧）

                ${lib.concatStringsSep " -> " cycle}

              提示：移除其中一个顺序约束，或将共享选项移动到公共模块
            ''
          else
            let
              next = lib.head ready;
            in
            go (lib.filter (name: name != next) remaining) (result ++ [ next ]);
    in
    go (sortNames enabled) [ ];

  buildGraph =
    {
      grouped,
      side,
      moduleGroups ? { },
    }:
    let
      sideModules = grouped.${side};
      groups =
        if !builtins.isAttrs moduleGroups then
          throw "moduleGroups 必须是属性集"
        else
          lib.mapAttrs (
            name: value:
            readGroupMembers {
              inherit name value side;
            }
          ) moduleGroups;
      rawNodes = builtins.deepSeq groups (
        lib.mapAttrs (
          name: paths:
          let
            metadata =
              grouped.meta.${name} or {
                path = "<unknown>";
                value = { };
              };
            raw = metadata.value;
            sideRaw = raw.${side} or { };
            sideConfig =
              if builtins.isAttrs sideRaw then
                sideRaw
              else
                throw ''
                  error: 模块依赖元数据无效

                  ${toString metadata.path} 中的 '${side}' 必须是属性集
                '';
            enableValue = sideConfig.enable or true;
            enabled =
              if builtins.isBool enableValue then
                enableValue
              else
                throw ''
                  error: 模块依赖元数据无效

                  ${toString metadata.path} 中的 '${side}.enable' 必须是布尔值
                '';
            field =
              key:
              lib.unique (
                readStringList {
                  field = key;
                  metaPath = metadata.path;
                  value = raw.${key} or [ ];
                }
                ++ readStringList {
                  field = "${side}.${key}";
                  metaPath = metadata.path;
                  value = sideConfig.${key} or [ ];
                }
              );
            requiresGroups = field "requiresGroups";
            unknownGroups = lib.filter (group: !builtins.hasAttr group groups) requiresGroups;
            groupRequires = lib.unique (lib.concatMap (group: groups.${group}) requiresGroups);
            directRequires = field "requires";
          in
          if !enabled then
            null
          else if unknownGroups != [ ] then
            throw ''
              error: 模块引用了未知模块组（${side} 侧）

                '${name}' 引用了：${lib.concatStringsSep ", " unknownGroups}
            ''
          else
            {
              inherit
                name
                paths
                directRequires
                groupRequires
                requiresGroups
                ;
              metaPath = metadata.path;
              requires = lib.unique (directRequires ++ groupRequires);
              after = field "after";
              before = field "before";
              wants = field "wants";
              conflicts = field "conflicts";
              provides = field "provides";
              requiresCapabilities = field "requiresCapabilities";
            }
        ) sideModules
      );
      baseNodes = lib.filterAttrs (_: node: node != null) rawNodes;
      names = builtins.attrNames baseNodes;
      references = lib.concatMap (
        name:
        let
          node = baseNodes.${name};
          refsFor = kind: targets: map (target: { inherit name kind target; }) targets;
        in
        refsFor "requires" node.requires
        ++ refsFor "after" node.after
        ++ refsFor "before" node.before
        ++ refsFor "wants" node.wants
        ++ refsFor "conflicts" node.conflicts
      ) names;
      unknown = lib.filter (ref: !builtins.hasAttr ref.target baseNodes) references;
      selfReferences = lib.filter (ref: ref.name == ref.target) references;
      contradictions = lib.concatMap (
        name:
        map (target: { inherit name target; }) (
          lib.filter (
            target:
            builtins.elem target baseNodes.${name}.conflicts || builtins.elem name baseNodes.${target}.conflicts
          ) baseNodes.${name}.requires
        )
      ) names;
      directEdges = lib.concatMap (
        name:
        let
          node = baseNodes.${name};
          makeEdges =
            kind: targets:
            map (target: {
              from = name;
              to = target;
              inherit kind;
            }) targets;
        in
        makeEdges "requires" node.directRequires
        ++ makeEdges "group" node.groupRequires
        ++ makeEdges "after" node.after
        ++ makeEdges "wants" node.wants
        ++ map (target: {
          from = target;
          to = name;
          kind = "before";
        }) node.before
      ) names;
      edges = lib.unique directEdges;
      nodes = lib.mapAttrs (
        name: node:
        node
        // {
          orderAfter = lib.unique (map (edge: edge.to) (lib.filter (edge: edge.from == name) edges));
        }
      ) baseNodes;
      checkedNodes =
        if unknown != [ ] then
          let
            details = lib.concatMapStringsSep "\n" (
              ref: "  - '${ref.name}' 通过 ${ref.kind} 引用了未知模块 '${ref.target}'"
            ) unknown;
          in
          throw ''
            error: 模块依赖引用了未知模块（${side} 侧）

            ${details}

            提示：请使用由目录路径推导的模块名，并确认目标模块存在于当前侧
          ''
        else if selfReferences != [ ] then
          let
            details = lib.concatMapStringsSep "\n" (
              ref: "  - '${ref.name}' 通过 '${ref.kind}' 引用了自身"
            ) selfReferences;
          in
          throw ''
            error: 模块依赖包含自引用（${side} 侧）

            ${details}
          ''
        else if contradictions != [ ] then
          let
            details = lib.concatMapStringsSep "\n" (
              item: "  - '${item.name}' 同时依赖并冲突于 '${item.target}'"
            ) contradictions;
          in
          throw ''
            error: 模块依赖元数据相互矛盾（${side} 侧）

            ${details}
          ''
        else
          nodes;
      order = topologicalOrder {
        nodes = checkedNodes;
        enabled = names;
        inherit side;
      };
      capabilities = lib.foldlAttrs (
        acc: name: node:
        lib.foldl (
          result: capability:
          result
          // {
            ${capability} = sortNames (lib.unique ((result.${capability} or [ ]) ++ [ name ]));
          }
        ) acc node.provides
      ) { } checkedNodes;
    in
    {
      inherit
        side
        edges
        order
        groups
        capabilities
        ;
      nodes = checkedNodes;
    };

  resolve =
    {
      graph,
      enabled,
      target,
      disabledReasons ? { },
    }:
    let
      enabledNames = sortNames (lib.unique enabled);
      missing = lib.concatMap (
        name:
        map (dependency: { inherit name dependency; }) (
          lib.filter (dependency: !builtins.elem dependency enabledNames) graph.nodes.${name}.requires
        )
      ) enabledNames;
      capabilityRequirements = lib.concatMap (
        name:
        map (
          capability:
          let
            providers = lib.filter (provider: builtins.elem provider enabledNames) (
              graph.capabilities.${capability} or [ ]
            );
          in
          {
            inherit name capability providers;
          }
        ) graph.nodes.${name}.requiresCapabilities
      ) enabledNames;
      missingCapabilities = lib.filter (item: item.providers == [ ]) capabilityRequirements;
      capabilityEdges = lib.concatMap (
        item:
        map (provider: {
          from = item.name;
          to = provider;
          kind = "capability";
          inherit (item) capability;
        }) item.providers
      ) capabilityRequirements;
      effectiveNodes = lib.mapAttrs (
        name: node:
        node
        // {
          orderAfter = lib.unique (
            node.orderAfter ++ map (edge: edge.to) (lib.filter (edge: edge.from == name) capabilityEdges)
          );
        }
      ) graph.nodes;
      conflicts = lib.unique (
        lib.concatMap (
          name:
          map (
            conflict:
            if name < conflict then
              {
                first = name;
                second = conflict;
              }
            else
              {
                first = conflict;
                second = name;
              }
          ) (lib.filter (conflict: builtins.elem conflict enabledNames) graph.nodes.${name}.conflicts)
        ) enabledNames
      );
      order = topologicalOrder {
        nodes = effectiveNodes;
        enabled = enabledNames;
        inherit (graph) side;
      };
    in
    if missing != [ ] then
      let
        details = lib.concatMapStringsSep "\n" (
          item:
          let
            reason = disabledReasons.${item.dependency} or "未被角色过滤选中";
          in
          "  - '${item.name}' 依赖 '${item.dependency}'，但后者未启用（${reason}）"
        ) missing;
      in
      throw ''
        error: ${target} 的模块依赖不完整（${graph.side} 侧）

        ${details}

        提示：启用所需模块，或移除依赖声明
      ''
    else if missingCapabilities != [ ] then
      let
        details = lib.concatMapStringsSep "\n" (
          item: "  - '${item.name}' 需要能力 '${item.capability}'，但没有已启用的 provider"
        ) missingCapabilities;
      in
      throw ''
        error: ${target} 的模块能力依赖不完整（${graph.side} 侧）

        ${details}
      ''
    else if conflicts != [ ] then
      let
        details = lib.concatMapStringsSep "\n" (
          item: "  - '${item.first}' 与 '${item.second}' 冲突"
        ) conflicts;
      in
      throw ''
        error: ${target} 启用了相互冲突的模块（${graph.side} 侧）

        ${details}

        提示：禁用其中一个冲突模块
      ''
    else
      {
        inherit order capabilityEdges capabilityRequirements;
      };
in
{
  inherit buildGraph resolve topologicalOrder;
}
