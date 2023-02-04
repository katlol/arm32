{ system ? builtins.currentSystem }:
let
  pkgsNative = (import ./nixpkgs.nix {});

  pkgs = (import ./nixpkgs.nix {
    crossSystem = (import <nixpkgs/lib>).systems.examples.raspberryPi;
    config = {
      packageOverrides = pkg: {
        python3 = pkgsNative.python3;
        pkg-config = pkgsNative.pkg-config;
        libseccomp = (static pkg.libseccomp);
        libcap = (static pkg.libcap).overrideAttrs(x: {
          postInstall = ''
            mkdir -p "$doc/share/doc/${x.pname}-${x.version}"
            cp License "$doc/share/doc/${x.pname}-${x.version}/"
            mkdir -p "$pam/lib/security"
            mv "$lib"/lib/security "$pam/lib"
          '';
        });
        systemd = (static pkg.systemd).overrideAttrs(x: {
          mesonFlags = x.mesonFlags ++ [
            "-Dstatic-libsystemd=true"
          ];
          postFixup = ''
            ${x.postFixup}
            sed -ri "s;$out/(.*);$nukedRef/\1;g" $lib/lib/libsystemd.a
          '';
        });
        yajl = (static pkg.yajl).overrideAttrs(x: {
          preConfigure = ''
            export CMAKE_STATIC_LINKER_FLAGS="-static"
          '';
        });
      };
    };
  });

  static = pkg: pkg.overrideAttrs(x: {
    doCheck = false;
    configureFlags = (x.configureFlags or []) ++ [
      "--without-shared"
      "--disable-shared"
    ];
    perlSupport = false;
    dontDisableStatic = true;
    enableSharedExecutables = false;
    enableStatic = true;
  });

  self = with pkgs; stdenv.mkDerivation rec {
    name = "crun";
    src = ./..;
    doCheck = false;
    enableParallelBuilding = true;
    strictDeps = true;

    depsBuildHost = [ autoreconfHook libtool gcc binutils ];
    nativeBuildInputs = [ python3 pkg-config ];
    buildInputs = [ glibc glibc.static libcap libseccomp yajl systemd ];
    #configureFlags = [
    #  "--disable-systemd"
    #  "--host=armv6l-unknown-linux-gnueabihf"
    #];
    prePatch = ''
      export PYTHON=${python3}/bin/python3
      export CFLAGS='-static'
      export LDFLAGS='-s -w -static-libgcc -static -Wl,--allow-multiple-definition'
      export EXTRA_LDFLAGS='-s -w -linkmode external -extldflags "-static -lm"'
      export CRUN_LDFLAGS='-all-static'
      export LIBS='${systemd.lib}/lib/libsystemd.a ${glibc.static}/lib/libc.a ${glibc.static}/lib/librt.a ${glibc.static}/lib/libpthread.a ${libseccomp.lib}/lib/libseccomp.a ${libcap.lib}/lib/libcap.a ${yajl}/lib/libyajl_s.a'
    '';
  };
in self
