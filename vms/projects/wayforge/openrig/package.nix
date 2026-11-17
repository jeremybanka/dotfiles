{ lib, buildNpmPackage, nodejs_24, python3, makeWrapper }:
buildNpmPackage {
  pname = "scrubs-openrig";
  version = "0.7.3";
  src = ./runtime;
  nodejs = nodejs_24;
  npmDepsHash = "sha256-8B2xTd3afPHe49nPnx2y4BOHk+GV6wpCfoR3WTx3ad0=";
  nativeBuildInputs = [ python3 makeWrapper ];
  # Published CLI contains its JavaScript. Dependency installation stays inside
  # the Nix build sandbox; install checks verify the selected native SQLite ABI.
  dontNpmBuild = true;
  env.npm_config_build_from_source = "true";
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/openrig" "$out/bin"
    cp -r node_modules "$out/lib/openrig/"
    makeWrapper ${nodejs_24}/bin/node "$out/bin/rig" \
      --add-flags "$out/lib/openrig/node_modules/@openrig/cli/dist/bin-wrapper.js"
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/rig" --version
    ${nodejs_24}/bin/node -e '
      const Database = require(process.argv[1]);
      const db = new Database(":memory:");
      if (db.prepare("select 1 as value").get().value !== 1) process.exit(1);
      db.close();
    ' "$out/lib/openrig/node_modules/better-sqlite3"
    runHook postInstallCheck
  '';
  meta = {
    description = "Pinned OpenRig control plane for the Scrubs clean runtime";
    homepage = "https://openrig.dev";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    mainProgram = "rig";
  };
}
