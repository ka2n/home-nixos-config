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

  # Add JSON override functionality
  postPatch = ''
    # Add import statement for readFileSync
    sed -i '3a import { readFileSync } from "node:fs";' src/deviceConfig.ts

    # Append JSON override code
    cat ${./json-override-append.ts} >> src/deviceConfig.ts

    # Patch builder.ts to use mergePayloadWithDelete
    # 1. Add mergePayloadWithDelete to the import from deviceConfig
    sed -i 's/import { IgnorePropertyPatterns } from "@\/deviceConfig";/import { IgnorePropertyPatterns, mergePayloadWithDelete } from "@\/deviceConfig";/' src/payload/builder.ts

    # 2. Replace shallow merge with deletion-aware merge
    sed -i 's/payload: { \.\.\.payload, \.\.\.override }/payload: mergePayloadWithDelete(payload, override)/' src/payload/builder.ts
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
