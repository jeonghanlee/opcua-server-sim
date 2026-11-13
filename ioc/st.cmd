on error break

# IOC startup for the composite model of the simulator, run through iocsh.bash
# of an EPICS distribution that provides the opcua module:
#
#   iocsh.bash -e <distribution tree> ioc/st.cmd
#
# The startup reads its settings from environment variables:
#
#   SIM_IOC_DIR   directory of this file and of composite.db
#   SIM_OPC_PORT  TCP port of the simulator on 127.0.0.1
#   SIM_SECURE_DIR  directory with the PKI store (pki/trusted/certs holds the
#                   server certificate as server-cert.der), the client
#                   certificate cert.pem, its key key.pem, and the identity
#                   file ident.txt with the lines user= and pass=
#
# The client certificate carries the subject alternative name
# urn:ioc@<host name>:EPICS:IOC, which is the application URI of the module.

module opcua

# Session OPC1: no security, anonymous. Session OPC2: signed and encrypted,
# user account from the identity file.
opcuaSession OPC1 opc.tcp://127.0.0.1:$(SIM_OPC_PORT) sec-mode=None
opcuaSubscription SUB1 OPC1 200

opcuaSetupPKI $(SIM_SECURE_DIR)/pki
opcuaClientCertificate $(SIM_SECURE_DIR)/cert.pem $(SIM_SECURE_DIR)/key.pem
opcuaSession OPC2 opc.tcp://127.0.0.1:$(SIM_OPC_PORT) sec-mode=SignAndEncrypt sec-policy=Basic256Sha256 sec-id=$(SIM_SECURE_DIR)/ident.txt
opcuaSubscription SUB2 OPC2 200

dbLoadRecords("$(SIM_IOC_DIR)/composite.db")

iocInit()
