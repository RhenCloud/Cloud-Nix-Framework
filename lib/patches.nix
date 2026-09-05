{
  local = path: path;

  # 固定到具体 commit，可复现性高于 PR patch URL
  # 用法：snowveil.patches.fromCommit { fetchpatch; owner; repo; rev; hash; }
  fromCommit =
    {
      fetchpatch,
      owner,
      repo,
      rev,
      hash,
    }:
    fetchpatch {
      url = "https://github.com/${owner}/${repo}/commit/${rev}.patch";
      inherit hash;
    };

  # 已弃用：PR patch URL 在 PR 再次推送后 hash 变化，可复现性差
  # 保留兼容；新代码请改用 fromCommit
  fromPR =
    {
      fetchpatch,
      owner,
      repo,
      pr,
      hash,
    }:
    builtins.trace
      "warning: snowveil.patches.fromPR is deprecated because PR patch URLs change hash on force-push; use snowveil.patches.fromCommit instead"
      fetchpatch
      {
        url = "https://github.com/${owner}/${repo}/pull/${pr}.patch";
        inherit hash;
      };
}
