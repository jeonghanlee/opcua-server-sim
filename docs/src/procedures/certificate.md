# Create the server certificate

The secured OPC UA endpoints use the certificate and private key in the model's `pki/` directory. `make run` prepares these files when needed.

## Prerequisites

- Have `make` and `openssl` available. The model must contain a `pki.cnf` certificate request.

From the checkout root, create the default model's certificate and key.

```bash
make certificate
```

The target reuses the existing key. It creates a certificate when missing or when the request or key is newer. The certificate's application URI in the subject alternative name must match `applicationDescription.applicationUri` in the [server configuration](../reference/server-config.md).

## Verification

List the certificate and key for `s7-1500-composite`.

```bash
ls models/s7-1500-composite/pki
```

Expected output.

```
server-cert.der
server-key.der
```
