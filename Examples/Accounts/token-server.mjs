// Signs any user. Demo only — never deploy.
//
// This runs on your server, never in your app. It stands in for your own backend so the Accounts example can try
// identify(token:). A real server takes the user from its own authenticated session and signs that user's id,
// name and email. This demo trusts the app's Authorization value as the user id, so anyone can sign as anyone.
//
//   RECEPTION_DEMO=1 RECEPTION_IDENTITY_SECRET=ids_… node Examples/Accounts/token-server.mjs
//   Run the Accounts example with RECEPTION_TOKEN_URL=http://localhost:3900/reception-token
//
// Zero dependencies: an HS256 JWT signed with the UTF-8 bytes of the identity secret, exactly as shown in the dashboard.
import { createHmac } from "node:crypto";
import { createServer } from "node:http";

if (process.env.RECEPTION_DEMO !== "1" || process.env.NODE_ENV === "production") {
  console.error("Refusing to start: this demo signs any user. Set RECEPTION_DEMO=1, and never run it in production.");
  process.exit(1);
}
const secret = process.env.RECEPTION_IDENTITY_SECRET;
if (!secret?.startsWith("ids_")) {
  console.error("Set RECEPTION_IDENTITY_SECRET to the identity secret from your Reception dashboard.");
  process.exit(1);
}
const port = Number(process.env.PORT ?? 3900);
const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");

function sign(claims) {
  const unsigned = `${encode({ alg: "HS256", typ: "JWT" })}.${encode(claims)}`;
  return `${unsigned}.${createHmac("sha256", secret).update(unsigned).digest("base64url")}`;
}

createServer((request, response) => {
  // Demo shortcut: the app's session credential is taken as the user id. Your server looks the user up instead.
  const userId = request.headers.authorization?.match(/^Bearer (.+)$/)?.[1];
  if (request.method !== "POST" || request.url !== "/reception-token" || !userId) {
    response.writeHead(404).end();
    return;
  }
  // exp is required; one hour covers an app session, and the app asks again at launch and sign-in.
  const token = sign({ user_id: userId, exp: Math.floor(Date.now() / 1000) + 3600 });
  response.writeHead(200, { "Content-Type": "application/json" }).end(JSON.stringify({ token }));
}).listen(port, "127.0.0.1", () => {
  console.log(`Demo token server on http://127.0.0.1:${port}/reception-token`);
});
