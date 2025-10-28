{ lib }:
{
  # Expand { systems = [ a b ]; .. } to [ { system = a; ..} { system = b; .. } ]
  flattenSystems = lib.foldl' (
    acc: version:
    acc
    ++ map (system: (builtins.removeAttrs version [ "systems" ]) // { inherit system; }) version.systems
  ) [ ];

  isCpu = version: version.cpu or false;
  isCuda = version: version ? cudaVersion;
  isMetal = version: version.metal or false;
  isRocm = version: version ? rocmVersion;
  isXpu = version: version ? xpuVersion;
}
