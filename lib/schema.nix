# Snowveil framework contract definition
# =======================================
# Enumerates outputs the Snowveil meta flake exposes so downstream tools
# (docs, IDE integrations) can reflect on them without triggering the
# "unknown flake output" warning Nix emits for unrecognised attribute
# names. See flake.nix for the generated `flakeOutputsSchema` output.
#
# Note: the mkFlake pipeline separately attaches a per-project schema to
# user flakes; see lib/default.nix for that declaration.

_:

{
  # Meta flake outputs (this repository).
  metaFlakeOutputs = {
    # Programming interface
    lib = "attribute set - Snowveil library, types, and utilities";

    # User-facing
    templates = "attribute set - flake templates (default)";

    # Quality assurance
    checks = "per-system derivations - framework self-tests and validations";
    devShells = "per-system attribute - development environment (default)";
    formatter = "per-system derivation - code formatting tool";

    # Documentation
    options = "per-system text file - NixOS options documentation (JSON)";
    flakeOutputsSchema = "attribute set - this schema documentation";
  };
}
