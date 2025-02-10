{
  lib,
  stdenv,
  makeWrapper,
  rsync,
}:

final: prev: {
  clr =
    let
      wrapperArgs = with final; [
        "--prefix PATH : $out/bin"
        "--prefix LD_LIBRARY_PATH : ${hsa-rocr}"
        "--set HIP_PLATFORM amd"
        "--set HIP_PATH $out"
        "--set HIP_CLANG_PATH ${llvm.clang}/bin"
        "--set DEVICE_LIB_PATH ${rocm-device-libs}/amdgcn/bitcode"
        "--set HSA_PATH ${hsa-rocr}"
        "--set ROCM_PATH $out"
      ];
    in
    stdenv.mkDerivation {
      pname = "rocm-clr";
      version = final.hipcc.version;

      nativeBuildInputs = [
        makeWrapper
        rsync
      ];

      propagatedBuildInputs = with final; [
        comgr
        rocm-device-libs
        hsa-rocr
        rocminfo
      ];

      dontUnpack = true;

      installPhase = with final; ''
        runHook preInstall

        mkdir -p $out

        for path in ${hipcc} ${hip-dev} ${hip-runtime-amd} ${rocm-opencl}; do
          rsync -a $path/ $out/
        done

        chmod -R u+w $out

        # Some build infra expects rocminfo to be in the clr package. Easier
        # to just symlink it than to patch everything.
        ln -s ${rocminfo}/bin/* $out/bin

        wrapProgram $out/bin/hipcc ${lib.concatStringsSep " " wrapperArgs}
        wrapProgram $out/bin/hipconfig ${lib.concatStringsSep " " wrapperArgs}
        wrapProgram $out/bin/hipcc.pl ${lib.concatStringsSep " " wrapperArgs}
        wrapProgram $out/bin/hipconfig.pl ${lib.concatStringsSep " " wrapperArgs}

        runHook postInstall
      '';

      passthru = {
        gpuTargets = lib.forEach [
          "803"
          "900"
          "906"
          "908"
          "90a"
          "940"
          "941"
          "942"
          "1010"
          "1012"
          "1030"
          "1100"
          "1101"
          "1102"
        ] (target: "gfx${target}");
      };

    };

  openmp = stdenv.mkDerivation {
    pname = "rocm-openmp";
    version = final.hipcc.version;

    nativeBuildInputs = [
      makeWrapper
      rsync
    ];

    dontUnpack = true;

    installPhase = with final; ''
      runHook preInstall

      mkdir -p $out

      for path in ${openmp-extras-dev} ${openmp-extras-runtime}; do
        rsync -a $path/lib/llvm/ $out/
      done

      runHook postInstall
    '';
  };
}
