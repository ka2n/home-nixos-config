{ lib
, buildNpmPackage
, fetchFromGitHub
, nodejs_24
}:

buildNpmPackage rec {
  pname = "e2m-hass-bridge";
  version = "1.15.1";

  src = fetchFromGitHub {
    owner = "nana4rider";
    repo = "e2m-hass-bridge";
    rev = "v${version}";
    hash = "sha256-1HQHAUDrkH67EpaGULh5C6yBXzndCQscAQcCftmoLTU=";
  };

  nodejs = nodejs_24;
  npmDepsHash = "sha256-/OWSc/mIZqRMh9nXwxtDjbqG+JGOyF/btb5rJXzKz7Y=";
  makeCacheWritable = true;

  patches = [
    ./add-json-override-support.patch
    ./fix-power-distribution-board-coefficient.patch
  ];

  # Add custom modules
  postPatch = ''
    # Copy coefficient fix module
    cp ${./apply-coefficient-fix.ts} src/payload/readonly/coefficient-fix.ts

    # Copy device config override module
    cp ${./deviceConfigOverride.ts} src/deviceConfigOverride.ts
  '';

  buildPhase = ''
    runHook preBuild
    npm run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/e2m-hass-bridge
    cp -r dist node_modules package.json $out/lib/e2m-hass-bridge/

    mkdir -p $out/bin
    cat > $out/bin/e2m-hass-bridge <<EOF
#!/bin/sh
exec ${nodejs_24}/bin/node --no-deprecation $out/lib/e2m-hass-bridge/dist/index.js "\$@"
EOF
    chmod +x $out/bin/e2m-hass-bridge

    runHook postInstall
  '';

  meta = with lib; {
    description = "Bridge between echonetlite2mqtt and Home Assistant MQTT discovery";
    homepage = "https://github.com/nana4rider/e2m-hass-bridge";
    license = licenses.isc;
    maintainers = [ ];
    platforms = platforms.linux;
    mainProgram = "e2m-hass-bridge";
  };
}
