const { execFileSync } = require("node:child_process");
const { mkdtempSync, readdirSync, rmSync } = require("node:fs");
const { tmpdir } = require("node:os");
const { join } = require("node:path");

exports.default = function afterSign({ electronPlatformName, appOutDir, packager }) {
  if (electronPlatformName !== "darwin" || process.env.SEKVONA_MAC_RELEASE !== "1") return;

  const app = join(appOutDir, `${packager.appInfo.productFilename}.app`);
  const resources = join(app, "Contents", "Resources");
  const unpacked = join(resources, "app.asar.unpacked");
  const arch = process.env.SEKVONA_MAC_RELEASE_ARCH;
  const expected = { arm64: "arm64", x64: "x86_64" }[arch];
  if (!expected) throw new Error(`Unsupported release architecture: ${arch}`);

  const impitBinding = `impit-node.darwin-${arch}.node`;
  const modules = readdirSync(unpacked, { recursive: true });
  const runtimeBindings = ["better_sqlite3.node", impitBinding].map((filename) => {
    const binding = modules.find((file) => file.endsWith(`/${filename}`));
    if (!binding) throw new Error(`Packaged native binding is missing: ${filename}`);
    return join(unpacked, binding);
  });
  for (const binary of [
    join(app, "Contents", "MacOS", packager.appInfo.productFilename),
    join(resources, "kopia", "kopia"),
    ...runtimeBindings,
  ]) {
    execFileSync("lipo", ["-verify_arch", expected, binary], { stdio: "inherit" });
  }
  const staging = mkdtempSync(join(tmpdir(), "sekvona-notarize-"));
  const archive = join(staging, `${packager.appInfo.productFilename}.zip`);
  const run = (command, args) => execFileSync(command, args, { stdio: "inherit" });
  try {
    run("codesign", ["--verify", "--deep", "--strict", app]);
    run("ditto", ["-c", "-k", "--keepParent", app, archive]);
    run("asc", ["notarization", "submit", "--file", archive, "--wait"]);
    // Staple the app before electron-builder creates the final ZIP and DMG.
    run("asc", ["notarization", "staple", "--file", app, "--confirm"]);
    run("asc", ["notarization", "validate", "--file", app]);
    run("spctl", ["--assess", "--type", "execute", app]);
  } finally {
    rmSync(staging, { recursive: true, force: true });
  }
};
