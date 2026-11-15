/** Test-only: generates a throwaway P-256 key pair in PKCS#8 PEM form. Never import at runtime. */

function base64(bytes: ArrayBuffer): string {
  let binary = "";
  for (const byte of new Uint8Array(bytes)) binary += String.fromCharCode(byte);
  return btoa(binary);
}

/** A fresh ES256 key pair: the private key as PKCS#8 PEM plus the public CryptoKey. */
export async function generateAppleTestKey(): Promise<{ pem: string; publicKey: CryptoKey }> {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, [
    "sign",
    "verify",
  ]);
  const der = await crypto.subtle.exportKey("pkcs8", pair.privateKey);
  const body = base64(der).match(/.{1,64}/g)?.join("\n") ?? "";
  return {
    pem: `-----BEGIN PRIVATE KEY-----\n${body}\n-----END PRIVATE KEY-----\n`,
    publicKey: pair.publicKey,
  };
}
