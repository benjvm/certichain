import { forge, verifyVersions } from "./common.mjs";
verifyVersions();
console.log(forge(...process.argv.slice(2)));
