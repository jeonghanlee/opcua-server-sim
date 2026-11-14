# Server configuration keys

The server reads its configuration from one JSON5 (JavaScript Object Notation, version 5) file that the open62541 library parses. This page lists the keys of the shipped file `models/s7-1500-composite/server.json5` with their values and meaning. The file holds comments that start with `//`.

## Application identity and build information

| Key | Value in the shipped file | Meaning |
| --- | --- | --- |
| `applicationDescription.applicationUri` | `urn:SIMATIC.S7-1500.OPC-UA.Application:PLC_1` | Application URI (uniform resource identifier) of the server. It is the entry at namespace index 1. The subject alternative name of the server certificate must equal it. |
| `applicationDescription.productUri` | `https://github.com/jeonghanlee/opcua-server-sim` | Product URI of this simulator. |
| `applicationDescription.applicationName` | locale `en-US`, text `SIMATIC.S7-1500.OPC-UA.Application:PLC_1` | Application name. |
| `applicationDescription.applicationType` | `0` | Application type: a server. |
| `buildInfo.productUri` | `https://github.com/jeonghanlee/opcua-server-sim` | Product URI in the BuildInfo of the Server object. |
| `buildInfo.manufacturerName` | `opcua-server-sim` | Manufacturer in the BuildInfo. |
| `buildInfo.productName` | `S7-1500 composite simulator` | Product name in the BuildInfo. |

The build number, the software version, and the build date of the BuildInfo come from the build, not from this file.

## Network and limits

| Key | Value in the shipped file | Meaning |
| --- | --- | --- |
| `serverUrls` | `opc.tcp://:4840` | Listen address list. The server listens on port 4840 on all interfaces. |
| `maxSessions` | `48` | Maximum number of sessions. |
| `maxNodesPerRead` | `1000` | Maximum items of one Read call. |
| `maxNodesPerWrite` | `1000` | Maximum items of one Write call. |
| `maxNodesPerRegisterNodes` | `1000` | Maximum items of one RegisterNodes call. |
| `maxMonitoredItemsPerCall` | `1000` | Maximum monitored items of one call. |
| `maxNodesPerBrowse` | `1000` | Maximum items of one Browse call. |
| `maxNodesPerTranslateBrowsePathsToNodeIds` | `1000` | Maximum items of one TranslateBrowsePathsToNodeIds call. |
| `maxNodesPerMethodCall` | `1` | Maximum methods of one Call service call. |

The limits follow the published system limits of a CPU (central processing unit) 1515 or 1516 with firmware V3.1. The simulation file keyword `limit` replaces `maxSessions` and the two interval minimums of a running server.

## Subscription limits of the server

| Key | Value in the shipped file | Meaning |
| --- | --- | --- |
| `subscriptionsEnabled` | `true` | Enables subscriptions. |
| `subscriptions.maxSubscriptions` | `30` | Maximum subscriptions over all sessions. |
| `subscriptions.maxSubscriptionsPerSession` | `50` | Maximum subscriptions of one session. |
| `subscriptions.maxMonitoredItemsPerSubscription` | `10000` | Maximum monitored items of one subscription. |
| `subscriptions.publishingIntervalLimits.min` | `100.0` | Smallest publishing interval in milliseconds. |
| `subscriptions.publishingIntervalLimits.max` | `3600000.0` | Largest publishing interval in milliseconds. |
| `subscriptions.samplingIntervalLimits.min` | `100.0` | Smallest sampling interval in milliseconds. |
| `subscriptions.samplingIntervalLimits.max` | `86400000.0` | Largest sampling interval in milliseconds. |

The CPU classes differ in these limits:

| CPU class | Sessions | Smallest sampling interval | Smallest publishing interval |
| --- | --- | --- | --- |
| 1511, 1512, 1513 | 32 | 100 ms | 200 ms |
| 1515, 1516 | 48 | 100 ms | 100 ms |
| 1517, 1518 | 64 | 10 ms | 10 ms |

## Security policies of the server

The key `securityPolicies` is a list. Each entry offers one security policy with the message security modes Sign and SignAndEncrypt. The policy None is always present.

| Key of an entry | Meaning |
| --- | --- |
| `policy` | URI of the security policy. |
| `certificate` | Path of the server certificate in DER (Distinguished Encoding Rules) form, relative to the model directory. |
| `privateKey` | Path of the private key in DER form, relative to the model directory. |

The shipped file offers these five policies, all with `pki/server-cert.der` and `pki/server-key.der`:

- `Basic128Rsa15`
- `Basic256`
- `Basic256Sha256`
- `Aes128_Sha256_RsaOaep`
- `Aes256_Sha256_RsaPss`

Remove an entry to disable its policy. Without a `pkiFolder` entry, the server accepts every client certificate.
