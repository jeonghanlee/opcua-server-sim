# Run an IOC against the simulator

An EPICS (Experimental Physics and Industrial Control System) IOC (input output controller) with the opcua device support module can read and write the tags of the simulator. This procedure starts the server and the IOC of the repository directory `ioc`, which opens one session without security and one session that is signed and encrypted, and reads two records through Channel Access.

## Prerequisites

- The prerequisites of [Run the simulator](run.md), including the open62541 installation path `<open62541_install_path>` and the NodeSet2 directory `<ua_nodeset_path>`.
- An EPICS distribution tree that holds `base/bin/<arch>/iocsh.bash`, `caget`, and the opcua device support module. This page names its root `<epics_tree>`.
- `openssl` in `PATH`.

1. In the repository root, start the server. The command runs until you stop it with Ctrl+C, so run the next steps in a second terminal:

   <!-- doc-check: background ready=simulating \d+ signals -->
   ```bash
   make run OPEN62541_PATH=<open62541_install_path> UA_NODESET_PATH=<ua_nodeset_path>
   ```

   `<open62541_install_path>` is the installation path of open62541. `<ua_nodeset_path>` is the directory of the OPC Foundation NodeSet2 files.

2. In the second terminal, in the repository root, create the PKI (public key infrastructure) store of the IOC. The store trusts the certificate of the server:

   ```bash
   mkdir -p tls/pki/trusted/certs tls/pki/issuers/certs
   ```

3. In the repository root, copy the server certificate into the store:

   ```bash
   cp models/s7-1500-composite/pki/server-cert.der tls/pki/trusted/certs
   ```

4. In the repository root, create the private key of the IOC:

   ```bash
   openssl genpkey -algorithm RSA -out tls/key.pem
   ```

5. In the repository root, create the self-signed certificate of the IOC. The subject alternative name is the application URI (uniform resource identifier) of the opcua module, `urn:ioc@<host_name>:EPICS:IOC`, and the shell variable `HOSTNAME` holds the host name:

   ```bash
   openssl req -x509 -key tls/key.pem -subj /O=ioc -addext subjectAltName=URI:urn:ioc@$HOSTNAME:EPICS:IOC -out tls/cert.pem
   ```

6. In the repository root, write the identity file of the secured session. It holds the user name and the password of the simulation file:

   ```bash
   printf 'user=simulator\npass=composite\n' > tls/ident.txt
   ```

7. In the repository root, write the settings that `ioc/st.cmd` reads from the environment: the directory of the IOC files, the port of the server, and the directory of the PKI store:

   ```bash
   printf 'SIM_IOC_DIR=ioc\nSIM_OPC_PORT=4840\nSIM_SECURE_DIR=tls\n' > tls/ioc.env
   ```

8. In the repository root, append the settings of Channel Access to the file. They restrict the search to the local host and use port 5164 instead of the default port 5064, so that another IOC on the host does not answer in its place:

   ```bash
   printf 'EPICS_CA_SERVER_PORT=5164\nEPICS_CA_ADDR_LIST=127.0.0.1\nEPICS_CA_AUTO_ADDR_LIST=NO\n' >> tls/ioc.env
   ```

9. In the repository root, start the IOC. The standard input of the IOC stays open through `sleep infinity`, because `iocsh.bash` ends when its input ends. The command runs until you stop it with Ctrl+C, so run the commands of the Verification section in a third terminal:

   <!-- doc-check: background ready=session OPC2: connected -->
   ```bash
   sleep infinity | env $(cat tls/ioc.env) <epics_tree>/base/bin/*/iocsh.bash -e <epics_tree> ioc/st.cmd
   ```

   `<epics_tree>` is the root of the EPICS distribution tree.

   The IOC logs the secured session when it has connected it:

   ```
   OPC UA session OPC2: connected as 'simulator' (username token) with security level 20 (mode=SignAndEncrypt; policy=Basic256Sha256)
   ```

## Verification

In the repository root, read two records of the IOC with Channel Access, with the settings of the file `tls/ioc.env`. `SIM:Static:Int` is the tag `"DataStatic"."myInt"` and `SIM:Mode` is the operating state:

```bash
env $(cat tls/ioc.env) <epics_tree>/base/bin/*/caget SIM:Static:Int SIM:Mode
```

The command prints the start value 42 of the tag and the value 8 of RUN:

```
SIM:Static:Int                 42
SIM:Mode                       8
```

To stop the IOC and the server, press Ctrl+C in the terminal of each. [Contents of the composite model](../reference/model-contents.md) lists the tags that the records of `ioc/composite.db` read.
