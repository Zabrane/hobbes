{ src, version, llvmVersions, gccConstraints, system, debug ? false, }:
final: prev:
with final;
let
  dbg = if debug == true then enableDebugging else (x: x);

  nativeBuildInputs = [ cmake ninja shake python27 ghc ];

  buildInputs = [ ncurses readline zlib python27 ]
                ++ (with haskellPackages; [ clock random shake heaps splitmix
                                            filepattern utf8-string
                                            js-dgtable js-jquery js-flot
                                          ]);

  cmakeFlags = [ "-GNinja" ];

  dontUseNinjaBuild = true;

  dontUseNinjaInstall = true;

  dontUseNinjaCheck = true;

  doCheck = true;

  doTarget = "test";

  dontStrip = debug;

  separateDebugInfo = debug;

  meta = with stdenv.lib; {
    description = "A language and an embedded JIT compiler";
    longDescription = ''
      Hobbes is a language, embedded compiler, and runtime for efficient
      dynamic expression evalution, data storage and analysis.
    '';
    license = licenses.asl20;
    maintainers = with maintainers; [ kthielen thmzlt smunix ];
  };

  when = c: m: if c then m else { };

  withGCC = { gccVersion ? 10 }:
    let
      gccPkgs = { gccVersion }:
        builtins.getAttr ("gcc" + (toString gccVersion) + "Stdenv") final;
      llvmPkgs = { llvmVersion }:
        builtins.getAttr ("llvmPackages_" + (toString llvmVersion)) final;
    in makeOverridable
    ({ llvmVersion, stdenv ? (gccPkgs { inherit gccVersion; }) }:
      stdenv.mkDerivation {
        pname = "hobbes-gcc-" + toString gccVersion + "-llvm-"
          + toString llvmVersion;
        inherit version src meta doCheck doTarget dontStrip cmakeFlags
          dontUseNinjaBuild dontUseNinjaInstall dontUseNinjaCheck;
        nativeBuildInputs = nativeBuildInputs;
        buildInputs = buildInputs
          ++ [ (llvmPkgs { inherit llvmVersion; }).llvm ];
        postPatch = ''
          substituteInPlace CMakeLists.txt \
             --replace "\''${CMAKE_SOURCE_DIR}" "${src}"
        '';
        buildPhase = ''
          ${shake}/bin/shake --color --report --timings -j -f build.ninja
        '';
      });

  withCLANG = let
    llvmPkgs = { llvmVersion }:
      builtins.getAttr ("llvmPackages_" + (toString llvmVersion)) final;
  in makeOverridable
  ({ llvmVersion, stdenv ? (llvmPkgs { inherit llvmVersion; }).stdenv }:
    stdenv.mkDerivation {
      pname = "hobbes-clang-" + (toString llvmVersion);
      inherit version src meta doCheck doTarget dontStrip cmakeFlags
        dontUseNinjaBuild dontUseNinjaInstall dontUseNinjaCheck;
      nativeBuildInputs = nativeBuildInputs;
      buildInputs = buildInputs ++ [ (llvmPkgs { inherit llvmVersion; }).llvm ];
      postPatch = ''
        substituteInPlace CMakeLists.txt \
           --replace "\''${CMAKE_SOURCE_DIR}" "${src}"
      '';
      buildPhase = ''
        ${shake}/bin/shake --color --report --timings -j -f build.ninja
      '';
      checkPhase = ''
        echo $(pwd)
        ls $(echo $(pwd))
        ./hobbes-test
      '';
      installPhase = ''
        make install
      '';
    });

in {
  hobbesPackages = when stdenv.isLinux (recurseIntoAttrs (builtins.listToAttrs
    (builtins.map (gccConstraint: {
      name = "gcc-" + toString gccConstraint.gccVersion;
      value = recurseIntoAttrs (builtins.listToAttrs (builtins.map
        (llvmVersion: {
          name = "llvm-" + toString llvmVersion;
          value = recurseIntoAttrs ({
            hobbes = dbg
              (callPackage (withGCC { inherit (gccConstraint) gccVersion; }) {
                inherit llvmVersion;
              });
          });
        }) gccConstraint.llvmVersions));
    }) gccConstraints))) // recurseIntoAttrs (builtins.listToAttrs (builtins.map
      (llvmVersion: {
        name = "clang-" + toString llvmVersion;
        value = recurseIntoAttrs ({
          hobbes = dbg (callPackage withCLANG { inherit llvmVersion; });
        });
      }) llvmVersions));
}