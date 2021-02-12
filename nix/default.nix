{
	pkgs ? import <nixpkgs> {},
	opam2nixBin ? null,

	# The official set of generated packages, which used to live in ./repo. The package selection
	# is restricted to this exact set due to the need for `digestMap` to be exhaustive, so this
	# is strongly bound to this exact checkout of `opam2nix-packages`, but it's an argument since
	# we inject it in release/default.nix
	opamRepository ? null,
}:
with pkgs;
let
	defaulted = value: dfl: if value == null then dfl else value;
	deps = {
		opam2nixBin = defaulted opam2nixBin (pkgs.callPackage "${(pkgs.nix-update-source.fetch ./release/src-opam2nix.json).src}/nix" {});
		opamRepository = defaulted opamRepository ((pkgs.nix-update-source.fetch ./release/src-opam-repository.json).src);
	};
in
let
	opam2nixBin = deps.opam2nixBin;
	opamRepository = deps.opamRepository;
	defaultPkgs = pkgs;

	addPassthru = attrs: drv:
		assert lib.isDerivation drv;
		drv.overrideAttrs (orig: { passthru = (orig.passthru or {}) // attrs; });

	# workaround https://github.com/NixOS/nixpkgs/issues/45933
	isStorePath = x: lib.isStorePath (builtins.toString x); # workaround https://github.com/NixOS/nixpkgs/issues/48743
	# to support IFD in nix/release, we build from `../` if it's already a store path
	src = if isStorePath ../. then ../. else (nix-update-source.fetch ./release/src.json).src;

	api = let

		## Specifications

		# A specification is attrset with a `name` field and optional `constraint`
		# field. Names and constraints are defined as in OPAM.
		#
		#   { name = "foo"; constraint = ">4.0.0"; }

		# Normalize a list of specs into a list of concatenated name+constraints
		specStrings = map ({ name, constraint ? "" }: "'${name}${constraint}'");

		# toSpec and toSpecs are utilities for allowing a shorthand string "x"
		# to stand for ({name = "x";})
		toSpec = obj: if builtins.isString obj
			then { name = obj; } # plain string
			else obj; # assume well-formed spec

		toSpecs = map toSpec;

		# get a list of package names from a specification collection
		packageNames = map ({ name, ... }: name);

		normalizePackageArgs = {
			name, src,
			packageName ? null,
			version ? null,
			opamFile ? null
		}:
			let parsedName = builtins.parseDrvName name; in
			{
				inherit src opamFile;
				package = defaulted packageName parsedName.name;
				version = defaulted version parsedName.version;
			};

		## Other stuff

		defaultOcamlAttr = "ocaml";
		configureOcamlImpl = { ocamlAttr, ocaml }: let
				attr = defaulted ocamlAttr defaultOcamlAttr;
				attrPath = lib.splitString "." attr;
			in {
				impl = defaulted ocaml (lib.getAttrFromPath attrPath pkgs);
				args = if ocaml == null
					then ["--ocaml-attr" attr]
					# Without unsafeDiscardOutputDependency, we end up with all the recursive build inputs
					# for ocaml and its dependencies (all the way to building stdenv from source).
					# See
					#  - https://github.com/NixOS/nix/commit/437077c39dd7abb44b2ab02cb9c6215d125bef04
					#  - https://github.com/NixOS/nix/issues/1245
					else ["--ocaml-drv" (builtins.unsafeDiscardOutputDependency ocaml.drvPath)];
			};
		parseOcamlVersion = { name, ... }: (builtins.parseDrvName name).version;

		defaultBasePackages = ["base-unix" "base-bigarray" "base-threads"]; #XXX this is a hack.
		defaultArgs = [];

		partitionAttrs = attrNames: attrs:
			with lib;
			[
				(filterAttrs (name: val: elem name attrNames) attrs) # named attrs
				(filterAttrs (name: val: !(elem name attrNames)) attrs) # other attrs
			];

		selectLax = {
			# used by `build`, so that you can combine import-time (world) options
			# with select-time options
			ocamlAttr ? null,
			ocaml ? null,
			ocamlVersion ? null,
			basePackages ? null,
			verbose ? null,
			specs,
			extraRepos ? [],
			args ? defaultArgs,
			OPAMSOLVERTIMEOUT ? null,
			... # ignored
		}:
			with lib;
			let
				ocamlSpec = configureOcamlImpl { inherit ocamlAttr ocaml; };
				extraRepoArgs = map (repo: "--repo \"${buildNixRepo repo}\"") extraRepos;
				ocamlVersionResolved = parseOcamlVersion ocamlSpec.impl;
				basePackagesResolved = defaulted basePackages defaultBasePackages;
				envCmd = ["env" "OCAMLRUNPARAM=b"] ++ (
					if OPAMSOLVERTIMEOUT == null then [] else ["OPAMSOLVERTIMEOUT=${toString OPAMSOLVERTIMEOUT}"]
				);
				cmd = concatStringsSep " " (
					envCmd ++
					[ "${opam2nixBin}/bin/opam2nix" "select" ] ++
					extraRepoArgs ++ [ # extra repos take priority over official one
						"--repo" generatedPackages
						"--dest" "$out"
						"--ocaml-version" (defaulted ocamlVersion ocamlVersionResolved)
						"--base-packages"
						(concatStringsSep "," basePackagesResolved)
					]
					++ (optional (defaulted verbose false) "--verbose")
					++ ocamlSpec.args
					++ args
					++ (specStrings specs)
				);
			in
			# possible format for "specs":
			# list of strings
			# object with key = pkgname, attr = versionSpec, or
			# list with intermixed strings / objects
			runCommand "opam-selection.nix" {} ''
				echo + ${cmd}
				${cmd}
			'';

		# builds a nix repo from an opam repo. Doesn't allow for customisation like
		# overrides etc, but useful for adding non-upstreamed opam packages into the world
		buildNixRepo = opamRepo: makeRepository {
			opamRepository = opamRepo;
		};

		selectStrict = {
			# exposed as `select`, so you know if you're using an invalid argument
			ocamlAttr ? null,
			ocamlVersion ? null,
			ocaml ? null,
			verbose ? null,
			basePackages ? null,
			specs,
			extraRepos ? [],
			args ? defaultArgs,
			OPAMSOLVERTIMEOUT ? null,
		}@conf: selectLax conf;

		buildOpamRepo = { package, version, src, opamFile ? null }:
			let opamFileSh = defaulted opamFile (lib.concatStringsSep ";" [
				"$(if [ -e '${src}/${package}.opam' ]; then echo '${package}.opam'"
				"else echo opam"
				"fi)"
			]); in
			stdenv.mkDerivation {
				name = "${package}-${version}-repo";
				buildCommand = ''
					if [ -z "${version}" ]; then
						echo "Error: no version specified for buildOpamRepo"
						exit 1
					fi
					dest="$out/packages/${package}/${package}.${version}"
					mkdir -p "$dest"
					opamFile="${opamFileSh}"
					if ! [ -n "$opamFile" -a -e "${src}/$opamFile" ]; then
						echo 'Error: opam file (`${package}.opam` or `opam`) not found in ${src}'
						exit 1
					fi
					cp "${src}/$opamFile" "$dest/opam"
					if [ -f "${src}" ]; then
						echo 'archive: "${src}"' > "$dest/url"
					else
						echo 'local: "${src}"' > "$dest/url"
					fi
				'';
			};

		buildOpamPackages = packages: drvAttrs:
			let
				normalizedPackages = map normalizePackageArgs packages;
				specOfPackage = { package, version, ... }: { name = package; constraint = "=" + version; };
				opamRepos = map buildOpamRepo normalizedPackages;

				opamAttrs = (drvAttrs // {
					specs = (drvAttrs.specs or []) ++ (map specOfPackage normalizedPackages);
					extraRepos = (drvAttrs.extraRepos or []) ++ opamRepos;
				});
			in
			{
				inherit opamRepos;
				packages = api.buildPackageSet opamAttrs;
				selection = api.selectionsFileLax opamAttrs;
			}
		;

		# Augment a set of generated packages. This builds a fixpoint on the generated
		# packages to apply customisations.
		filterWorldArgs = attrs: {
			pkgs = attrs.pkgs or null;
			overrides = attrs.overrides or null;
		};
		applyWorld = {
			select,
			pkgs ? null,
			overrides ? null,
		}:
			let
			noop = ({super, self}: {});
			finalPkgs = defaulted pkgs defaultPkgs;
			lib = finalPkgs.lib;
			fix = f: let result = f result; in result;
			extend = rattrs: f: self: let super = rattrs self; in super // f { inherit self super; };
			defaultOverrides = import ../repo/overrides;
			userOverrides = defaulted overrides noop;
			format_version = 3;

			# packages have structure <name>.<version> - we want to combine all versions across
			# repos without merging the derivation attributes of individual versions
			mergeTwoLevels = lib.recursiveUpdateUntil (parent: l: r: (lib.length parent) == 1);
			mergeOpamPackages = self:
				let
					invokeRepo = repo: (import repo) self;
					addRepo = acc: repo: mergeTwoLevels (invokeRepo repo) acc;
				in
				lib.foldl addRepo {} self.repositories;
		in
			assert format_version == opam2nixBin.format_version;
			fix
			(extend
				(extend
					(extend
						(self: {
							pkgs = finalPkgs;
							opam2nix = opam2nixBin;
							opamPackages = mergeOpamPackages self;
						})
						select)
					defaultOverrides)
				userOverrides)
		;

		defaultOpam2nixBin = opam2nixBin;

		makeRepository = {
			opamRepository,
			opam2nixBin ? null,
			packages ? null,
			numVersions ? null,
			digestMap ? null,
			ignoreBroken ? null,
			unclean ? null,
			verbose ? null,
			offline ? null,
			dest ? null,
		}: with lib; (
			let
			finalDest = defaulted dest "$out";
			finalOpam2nixBin = defaulted opam2nixBin defaultOpam2nixBin;
			optionalArg = prefix: arg: if arg == null then [] else [prefix "'${arg}'"];
			cmd = [
				"${finalOpam2nixBin}/bin/opam2nix" "generate"
				"--src" opamRepository
				"--dest" finalDest
			]
				++ (optional (defaulted ignoreBroken false) "--ignore-broken")
				++ (optional (defaulted unclean false) "--unclean")
				++ (optional (defaulted verbose false) "--verbose")
				++ (optional (defaulted offline true) "--offline")
				++ (optionalArg "--num-versions" numVersions)
				++ (optionalArg "--digest-map" digestMap)
				++ map (p: "'${p}'") (defaulted packages ["*"])
			; in
			stdenv.mkDerivation rec {
				name = "opam2nix-generated-packages";
				shellHook = ''
					if [ '${finalDest}' == '$out' ]; then
						echo 'ERROR: dest must be set in shell mode (opam2nix.makeRepository)'
						exit 1
					fi
					${buildCommand}
					exit 0
				'';
				buildCommand = ''
					mkdir -p "${finalDest}"
					echo "+ " ${concatStringsSep " " cmd}
					${concatStringsSep " " cmd}
				'';
			}
		);

		defaultOpamRepository = opamRepository;

		generateOfficialPackages = {
			opamRepository ? defaultOpamRepository,
			digestMap ? ../repo/digest.json,
			opam2nixBin ? null,
			dest ? null,
			unclean ? null,
			offline ? null,
			verbose ? null,
			packages ? null
		}: makeRepository {
			inherit opamRepository digestMap dest unclean packages opam2nixBin offline verbose;
			# numVersions = "*.*.2";
			ignoreBroken = true;
		};

		generatedPackages = generateOfficialPackages { offline = true; };

	in {
		# low-level selecting & importing
		selectionsFile = selectStrict;
		selectionsFileLax = selectLax;
		importSelectionsFile = selection_file: world:
			(applyWorld ({
				inherit pkgs; # defaults, overrideable
				select = lib.info "Importing selections: ${selection_file}" (import selection_file);
			} // world)).selection;
		importSelectionsFileLax = selection_file: world:
			api.importSelectionsFile selection_file (filterWorldArgs world);

		inherit buildOpamRepo buildNixRepo packageNames toSpec toSpecs buildOpamPackages opam2nixBin;

		# used in build scripts
		_generateOfficialPackages = generateOfficialPackages;

		# get the implementation of each specified package in the selections.
		# Selections are the result of `build` (or importing the selection file)
		packagesOfSelections = specs: selections:
			map (name: builtins.getAttr name selections) (packageNames specs);

		# Select-and-import. Returns a selection object with attributes for each extant package
		buildPackageSet = args: (api.importSelectionsFileLax (selectLax args) args);

		# like just the attribute values from `buildPackageSet`, but also includes ocaml dependency
		build = { specs, ... }@args:
			let selections = (api.buildPackageSet args); in
			[selections.ocaml] ++ (api.packagesOfSelections specs selections);

		# Takes a single spec and only returns a single selected package matching that.
		buildPackageSpec = spec: args: builtins.getAttr spec.name (api.buildPackageSet ({ specs = [spec]; } // args));

		# Like `buildPackageSpec` but only returns the single selected package.
		buildPackage = name: api.buildPackageSpec { inherit name; };

		buildOpamPackage = attrs:
			with lib;
			let
				partitioned = partitionAttrs ["name" "src" "opamFile" "packageName" "version" ] attrs;
				packageAttrs = elemAt partitioned 0;
				drvAttrs = removeAttrs (elemAt partitioned 1) ["passthru"];
				extraSpecs = drvAttrs.specs or null;
				result = buildOpamPackages [packageAttrs] drvAttrs;
				normalizedPackage = normalizePackageArgs packageAttrs;
				passthru = {
					opam2nix = {
						inherit (result) packages selection;
						repo = elemAt result.opamRepos 0;
					};
				} // (attrs.passthru or {});

				getPkg = name: builtins.getAttr name result.packages;
				baseDrv = getPkg normalizedPackage.package;
				# if `specs` is passed, make the returned derivation depend on those extra selections
				drv = if extraSpecs == null then baseDrv else
					baseDrv.overrideAttrs (o: {
						buildInputs = (o.buildInputs or []) ++ (map (spec: getPkg spec.name) extraSpecs);
					});
			in
			addPassthru passthru drv;

		opamRepository = defaultOpamRepository;
		opamPackages =
			let
				opamPackages = import generatedPackages {};
				realVersion = v: v != "latest";
				make = attr:
					let
						buildArgs = { ocamlAttr = "ocaml-ng.${attr}.ocaml"; };
					in
					lib.mapAttrs (name: versionPackages:
						let versions = lib.filter realVersion (lib.attrNames versionPackages); in
						addPassthru (
							lib.listToAttrs (map (version: {
								name = builtins.replaceStrings ["."] ["_"] version;
								value = api.buildPackageSpec { inherit name; constraint = "=${version}"; } buildArgs;
							}) versions)
						) (api.buildPackage name buildArgs)
					) opamPackages;
			in
			addPassthru {
				"4_06" = make "ocamlPackages_4_06";
			} generatedPackages;
	};
in
api
