world:
let
    fetchurl = pkgs.fetchurl;
    inputs = lib.filter (dep: dep != true && dep != null)
    ([  ] ++ (lib.attrValues opamDeps));
    lib = pkgs.lib;
    opam2nix = world.opam2nix;
    opamDeps = 
    {
      base-bigarray = opamSelection.base-bigarray or null;
      base-bytes = opamSelection.base-bytes;
      base-threads = opamSelection.base-threads or null;
      base-unix = opamSelection.base-unix or null;
      cppo = opamSelection.cppo;
      ocaml = opamSelection.ocaml;
      ocamlbuild = opamSelection.ocamlbuild;
      ocamlfind = opamSelection.ocamlfind;
      result = opamSelection.result;
      sequence = opamSelection.sequence or null;
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
  name = "containers-0.20";
  opamEnv = builtins.toJSON 
  {
    deps = opamDeps;
    files = null;
    name = "containers";
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
    sha256 = "0sr8ip1jpsyc8dxxdl6kk429pzhkalmg05rq0habj9dwhxnbzzym";
    url = "https://github.com/c-cube/ocaml-containers/archive/0.20.tar.gz";
  };
}

