import { build } from "esbuild";

await build({
  entryPoints: ["src/main.jsx"],
  bundle: true,
  minify: true,
  format: "iife",
  target: "safari17",
  outfile: "../App/Resources/flow.js",
  define: { "process.env.NODE_ENV": '"production"' },
  loader: { ".woff2": "dataurl" },
  logLevel: "info",
});
