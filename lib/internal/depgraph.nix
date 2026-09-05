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
        supportedFieldsSet = {
          common = true;
          nixos = true;
          home = true;
        };
        unknownFields = lib.filter (field: !builtins.hasAttr field supportedFieldsSet) (
          builtins.attrNames value
        );
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
      enabledNames = sortNames (lib.unique enabled);
      enabledSet = lib.genAttrs enabledNames (_: true);
      dependencies = builtins.listToAttrs (
        map (
          name:
          lib.nameValuePair name (
            lib.filter (dependency: builtins.hasAttr dependency enabledSet) nodes.${name}.orderAfter
          )
        ) enabledNames
      );
      dependentPairs = lib.concatMap (
        name: map (dependency: { inherit name dependency; }) dependencies.${name}
      ) enabledNames;
      dependents = lib.mapAttrs (_: pairs: sortNames (map (pair: pair.name) pairs)) (
        lib.groupBy (pair: pair.dependency) dependentPairs
      );
      initialIndegree = builtins.listToAttrs (
        map (name: lib.nameValuePair name (builtins.length dependencies.${name})) enabledNames
      );
      initialReady = lib.filter (name: initialIndegree.${name} == 0) enabledNames;

      findCycle =
        indegree:
        let
          remaining = lib.filter (name: indegree.${name} > 0) enabledNames;
          remainingSet = lib.genAttrs remaining (_: true);
          follow =
            current: path:
            if builtins.elem current path then
              (dropUntil current path) ++ [ current ]
            else
              let
                candidates = sortNames (
                  lib.filter (name: builtins.hasAttr name remainingSet) dependencies.${current}
                );
              in
              follow (lib.head candidates) (path ++ [ current ]);
        in
        follow (lib.head remaining) [ ];

      go =
        remainingCount: ready: indegree: result:
        if remainingCount == 0 then
          lib.reverseList result
        else if ready == [ ] then
          let
            cycle = findCycle indegree;
          in
          throw ''
            error: 检测到模块循环依赖（${side} 侧）

              ${lib.concatStringsSep " -> " cycle}

            提示：移除其中一个顺序约束，或将共享选项移动到公共模块
          ''
        else
          let
            next = lib.head ready;
            deps = dependents.${next} or [ ];
            newVals = map (dep: lib.nameValuePair dep (indegree.${dep} - 1)) deps;
            newIndegree = indegree // builtins.listToAttrs newVals;
            newlyReady = lib.filter (nv: nv.value == 0) newVals;
            nextReady = sortNames (lib.tail ready ++ map (nv: nv.name) newlyReady);
          in
          go (remainingCount - 1) nextReady newIndegree ([ next ] ++ result);
    in
    go (builtins.length enabledNames) initialReady initialIndegree [ ];

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
      conflictSets = lib.mapAttrs (_: node: lib.genAttrs node.conflicts (_: true)) baseNodes;
      contradictions = lib.concatMap (
        name:
        map (target: { inherit name target; }) (
          lib.filter (
            target: builtins.hasAttr target conflictSets.${name} || builtins.hasAttr name conflictSets.${target}
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
      edgesBySource = lib.groupBy (edge: edge.from) directEdges;
      orderAfterMap = lib.mapAttrs (
        name: _: lib.unique (map (edge: edge.to) (edgesBySource.${name} or [ ]))
      ) baseNodes;
      nodes = lib.mapAttrs (name: node: node // { orderAfter = orderAfterMap.${name}; }) baseNodes;
      edges = lib.unique directEdges;
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
      capabilityPairs = lib.concatMap (
        name: map (capability: { inherit name capability; }) checkedNodes.${name}.provides
      ) (builtins.attrNames checkedNodes);
      capabilities = lib.mapAttrs (_: pairs: sortNames (lib.unique (map (pair: pair.name) pairs))) (
        lib.groupBy (pair: pair.capability) capabilityPairs
      );
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
      enabledSet = lib.genAttrs enabledNames (_: true);
      missing = lib.concatMap (
        name:
        map (dependency: { inherit name dependency; }) (
          lib.filter (dependency: !builtins.hasAttr dependency enabledSet) graph.nodes.${name}.requires
        )
      ) enabledNames;
      capabilityRequirements = lib.concatMap (
        name:
        map (
          capability:
          let
            providers = lib.filter (provider: builtins.hasAttr provider enabledSet) (
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
      capabilityEdgesBySource = lib.groupBy (edge: edge.from) capabilityEdges;
      effectiveOrderAfterMap = lib.mapAttrs (
        name: node:
        lib.unique (node.orderAfter ++ map (edge: edge.to) (capabilityEdgesBySource.${name} or [ ]))
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
          ) (lib.filter (conflict: builtins.hasAttr conflict enabledSet) graph.nodes.${name}.conflicts)
        ) enabledNames
      );
      order =
        if capabilityEdges == [ ] then
          lib.filter (name: builtins.hasAttr name enabledSet) graph.order
        else
          topologicalOrder {
            nodes = lib.mapAttrs (name: oa: { orderAfter = oa; }) effectiveOrderAfterMap;
            enabled = enabledNames;
            inherit (graph) side;
          };
    in
    if missing != [ ] then
      let
        details = lib.concatMapStringsSep "\n" (
          item:
          let
            reason = disabledReasons.${item.dependency} or "not selected by role filter";
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
