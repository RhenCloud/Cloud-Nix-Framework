{
  local = path: path;

  fromPR =
    {
      fetchpatch,
      owner,
      repo,
      pr,
      hash,
    }:
    fetchpatch {
      url = "https://github.com/${owner}/${repo}/pull/${pr}.patch";
      inherit hash;
    };
}
