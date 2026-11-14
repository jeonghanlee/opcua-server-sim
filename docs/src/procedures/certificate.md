# Create the server certificate

The secured endpoints of the server need an application certificate and its private key, which the server configuration names as `pki/server-cert.der` and `pki/server-key.der` in the model directory. This procedure creates both files for the model that carries the request file `pki.cnf`.

## Prerequisites

- A Linux host with `make` and `openssl` in `PATH`.

The procedure has one step.

- In the repository root, create the key and the self-signed certificate:

  ```bash
  make certificate
  ```

The target creates an RSA (Rivest-Shamir-Adleman) key of `CERT_KEY_BITS` bits (2048) and a certificate that is valid for `CERT_DAYS` days (3650). The certificate is self-signed, which means that the key of the server signed it, and it carries the subject alternative name (the identities that the certificate vouches for) `URI:urn:SIMATIC.S7-1500.OPC-UA.Application:PLC_1`, which must equal `applicationUri` in `server.json5`. The target creates the files when they are missing, so remove the two files in `models/s7-1500-composite/pki` before you run it with other values of the variables. A repeated run keeps the key, and it creates the certificate again when `pki.cnf` or the key is newer than the certificate. The request file also names `localhost` and `127.0.0.1`; add the names and addresses under which clients reach the server to it.

## Verification

List the files of the certificate directory:

```bash
ls models/s7-1500-composite/pki
```

The command prints:

```
server-cert.der
server-key.der
```
