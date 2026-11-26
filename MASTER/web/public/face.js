"use strict";

const FACE_MODULES = window.MASTER_ASSET_PATHS?.faceModulesList;
if (!Array.isArray(FACE_MODULES) || FACE_MODULES.length === 0) {
  throw new Error("face boot manifest missing faceModulesList");
}

for (const modulePath of FACE_MODULES) {
  const url = window.MASTER_ASSET_PATHS?.faceModules?.[modulePath]
    || window.MASTER_ASSET_PATHS?.[modulePath]
    || modulePath;
  await import(url);
}

const FACE_RUNTIME = window.MASTER_ASSET_PATHS?.faceRuntime
  || window.MASTER_ASSET_PATHS?.faceModules?.["face.runtime.js"]
  || "face.runtime.js";

await import(new URL(FACE_RUNTIME, document.baseURI).href);
