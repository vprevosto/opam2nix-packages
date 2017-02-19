world:
let
    fetchurl = pkgs.fetchurl;
    inputs = lib.filter (dep: dep != true && dep != null)
    ([  ] ++ (lib.attrValues opamDeps));
    lib = pkgs.lib;
    opam2nix = world.opam2nix;
    opamDeps = 
    {
      bap-dwarf = opamSelection.bap-dwarf;
      bap-std = opamSelection.bap-std;
      bitstring = opamSelection.bitstring;
      camlp4 = opamSelection.camlp4;
      ocaml = opamSelection.ocaml;
      ocamlfind = opamSelection.ocamlfind or null;
    };
    opamSelection = world.opamSelection;
    pkgs = world.pkgs;
in
pkgs.stdenv.mkDerivation 
{
  buildInputs = inputs;
  buildPhase = "${opam2nix}/bin/opam2nix invoke build";
  configurePhase = "true";
  installPhase = "${opam2nix}/bin/opam2nix invoke install";
  name = "bap-elf-1.2.0";
  opamEnv = builtins.toJSON 
  {
    deps = opamDeps;
    files = null;
    name = "bap-elf";
    ocaml-version = world.ocamlVersion;
    spec = ./opam;
  };
  passthru = 
  {
    opamSelection = opamSelection;
  };
  propagatedBuildInputs = inputs;
  src = fetchurl 
  {
    sha256 = "033s16s0igrhqppjarv101483p8fbpwnn0mm64f9gmipc9m5x661";
    url = "https://github.com/BinaryAnalysisPlatform/bap/archive/v1.2.0.tar.gz";
  };
}

