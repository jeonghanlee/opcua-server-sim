/*
 * Command-line OPC UA client for checking a running server.
 *
 * usage: opcua-probe [-u <user> -p <password>] [-c <cert.der> -k <key.der>
 *                    -P <policy> -m <2|3>] <endpoint-url> <command> [...]
 *
 * Commands:
 *   read <node>                          value of a Variable
 *   write <node> <type> <value>          write a scalar, or an array with <type>[] and <v1>,<v2>,...
 *   call <object> <method> [<arg> ...]   call a Method; <arg> is <type>:<value>
 *                                        or <type>[]:<v1>,<v2>,...
 *   browse <node>                        forward hierarchical references
 *   refs <node>                          all references in both directions
 *   endpoints                            endpoints of the server
 *   events <node> <seconds> [<field> ...] events reported by an Object; each <field> is
 *                                        a field of SimaticEventType, printed as <field>=<value>;
 *                                        an associated value is printed as
 *                                        <switch>:<member>:<value>; an alarm with
 *                                        a state that holds no value prints the
 *                                        switch 0, and an event that holds no value
 *                                        has no such field and prints nothing
 *   intervals [<node>]                   revised intervals for a request of 1 ms on a node
 *                                        (CurrentTime when none is given)
 *   sessions                             opens sessions until one is refused
 *   subscriptions <count>                creates up to <count> subscriptions
 *   items <count>                        creates <count> monitored items in one subscription
 *
 * A type is one of bool, sbyte, byte, int16, uint16, int32, uint32, int64,
 * uint64, float, double, datetime (100 ns ticks since 1601), string,
 * bytestring (hexadecimal digits), or text (LocalizedText).
 *
 * The first word of the output of read, write, and call is the status name.
 * A session secured with a certificate uses -P with the policy name, for
 * example Basic256Sha256, and -m with 2 for Sign or 3 for SignAndEncrypt; the
 * application URI of the client certificate must be CLIENT_URI. The exit
 * status is 0 when the command ran, 1 when the connection failed, and 2 for a
 * usage error.
 */

#include <open62541/client.h>
#include <open62541/client_config_default.h>
#include <open62541/client_highlevel.h>
#include <open62541/client_subscriptions.h>
#include <open62541/plugin/certificategroup_default.h>
#include <open62541/plugin/log_stdout.h>
#include <open62541/plugin/securitypolicy_default.h>

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define EXIT_USAGE 2
#define CLIENT_URI "urn:opcua-server-sim:probe"
#define POLICY_URI_PREFIX "http://opcfoundation.org/UA/SecurityPolicy#"
#define EVENT_LOCALE "en-US"
#define EVENT_QUEUE_SIZE 100
#define EVENT_STEP_MS 100
#define MAX_ARGUMENTS 32
#define EVENT_BASE_FIELDS 9
#define MAX_EVENT_FIELDS 16
#define SIMATIC_NAMESPACE 3
#define SIMATIC_EVENT_TYPE 1804
#define SIMATIC_ALARM_TYPE 1805
#define MAX_SESSIONS_TRIED 200
#define ITEMS_PER_CALL 1000
#define ITEM_SAMPLING_MS 60000.0

typedef struct {
    const char *user;
    const char *password;
    const char *certificate;
    const char *key;
    const char *policy;
    int mode;
} Options;

typedef struct {
    const char *name;
    const UA_DataType *type;
} TypeName;

static const TypeName type_names[] = {
    {"bool", &UA_TYPES[UA_TYPES_BOOLEAN]},   {"sbyte", &UA_TYPES[UA_TYPES_SBYTE]},
    {"byte", &UA_TYPES[UA_TYPES_BYTE]},      {"int16", &UA_TYPES[UA_TYPES_INT16]},
    {"uint16", &UA_TYPES[UA_TYPES_UINT16]},  {"int32", &UA_TYPES[UA_TYPES_INT32]},
    {"uint32", &UA_TYPES[UA_TYPES_UINT32]},  {"int64", &UA_TYPES[UA_TYPES_INT64]},
    {"uint64", &UA_TYPES[UA_TYPES_UINT64]},  {"float", &UA_TYPES[UA_TYPES_FLOAT]},
    {"double", &UA_TYPES[UA_TYPES_DOUBLE]},  {"datetime", &UA_TYPES[UA_TYPES_DATETIME]},
    {"string", &UA_TYPES[UA_TYPES_STRING]},  {"bytestring", &UA_TYPES[UA_TYPES_BYTESTRING]},
    {"text", &UA_TYPES[UA_TYPES_LOCALIZEDTEXT]},
};

static const UA_DataType *
find_type(const char *name) {
    for(size_t i = 0; i < sizeof(type_names) / sizeof(type_names[0]); i++) {
        if(strcmp(type_names[i].name, name) == 0)
            return type_names[i].type;
    }
    return NULL;
}

/* Reads a whole file into a byte string. Returns an empty byte string when
 * the file cannot be read. */
static UA_ByteString
read_file(const char *path) {
    UA_ByteString content = UA_BYTESTRING_NULL;
    FILE *fp = fopen(path, "rb");
    long size = 0;

    if(!fp)
        return content;
    if(fseek(fp, 0, SEEK_END) == 0 && (size = ftell(fp)) >= 0 && fseek(fp, 0, SEEK_SET) == 0 &&
       UA_ByteString_allocBuffer(&content, (size_t)size) == UA_STATUSCODE_GOOD &&
       fread(content.data, 1, content.length, fp) != content.length)
        UA_ByteString_clear(&content);
    fclose(fp);
    return content;
}

/* Converts hexadecimal digits to bytes. Returns false for an odd length or a
 * character that is not a hexadecimal digit. */
static UA_Boolean
parse_hex(UA_ByteString *out, const char *text) {
    size_t length = strlen(text);

    if(length % 2 != 0 || UA_ByteString_allocBuffer(out, length / 2) != UA_STATUSCODE_GOOD)
        return length == 0;
    for(size_t i = 0; i < out->length; i++) {
        char pair[3] = {text[2 * i], text[2 * i + 1], '\0'};
        char *end = NULL;
        unsigned long byte = strtoul(pair, &end, 16);
        if(*end != '\0') {
            UA_ByteString_clear(out);
            return false;
        }
        out->data[i] = (UA_Byte)byte;
    }
    return true;
}

/* Stores the text as one value of the data type. Returns false when the text
 * is not a valid value of that type. */
static UA_Boolean
parse_scalar(void *dst, const UA_DataType *type, const char *text) {
    char *end = NULL;

    errno = 0;
    switch(type->typeKind) {
    case UA_DATATYPEKIND_BOOLEAN:
        *(UA_Boolean *)dst = strcmp(text, "true") == 0 || strcmp(text, "1") == 0;
        return true;
    case UA_DATATYPEKIND_SBYTE:
        *(UA_SByte *)dst = (UA_SByte)strtol(text, &end, 0);
        break;
    case UA_DATATYPEKIND_BYTE:
        *(UA_Byte *)dst = (UA_Byte)strtoul(text, &end, 0);
        break;
    case UA_DATATYPEKIND_INT16:
        *(UA_Int16 *)dst = (UA_Int16)strtol(text, &end, 0);
        break;
    case UA_DATATYPEKIND_UINT16:
        *(UA_UInt16 *)dst = (UA_UInt16)strtoul(text, &end, 0);
        break;
    case UA_DATATYPEKIND_INT32:
        *(UA_Int32 *)dst = (UA_Int32)strtol(text, &end, 0);
        break;
    case UA_DATATYPEKIND_UINT32:
        *(UA_UInt32 *)dst = (UA_UInt32)strtoul(text, &end, 0);
        break;
    case UA_DATATYPEKIND_INT64:
    case UA_DATATYPEKIND_DATETIME:
        *(UA_Int64 *)dst = strtoll(text, &end, 0);
        break;
    case UA_DATATYPEKIND_UINT64:
        *(UA_UInt64 *)dst = strtoull(text, &end, 0);
        break;
    case UA_DATATYPEKIND_FLOAT:
        *(UA_Float *)dst = strtof(text, &end);
        break;
    case UA_DATATYPEKIND_DOUBLE:
        *(UA_Double *)dst = strtod(text, &end);
        break;
    case UA_DATATYPEKIND_STRING:
        *(UA_String *)dst = UA_STRING_ALLOC(text);
        return true;
    case UA_DATATYPEKIND_BYTESTRING:
        return parse_hex((UA_ByteString *)dst, text);
    case UA_DATATYPEKIND_LOCALIZEDTEXT:
        *(UA_LocalizedText *)dst = UA_LOCALIZEDTEXT_ALLOC(EVENT_LOCALE, text);
        return true;
    default:
        return false;
    }
    return end != text && *end == '\0' && errno == 0;
}

/* Builds a Variant from "<type>:<value>" or "<type>[]:<v1>,<v2>,...". */
static UA_Boolean
parse_argument(UA_Variant *variant, char *argument) {
    char *colon = strchr(argument, ':');
    size_t type_length = 0;
    UA_Boolean is_array = false;
    const UA_DataType *type = NULL;
    char *list = NULL;
    size_t count = 1;
    void *data = NULL;
    char *save = NULL;
    size_t i = 0;

    if(!colon)
        return false;
    *colon = '\0';
    type_length = strlen(argument);
    if(type_length > 2 && strcmp(argument + type_length - 2, "[]") == 0) {
        argument[type_length - 2] = '\0';
        is_array = true;
    }
    type = find_type(argument);
    if(!type)
        return false;

    if(!is_array) {
        data = UA_new(type);
        if(!data || !parse_scalar(data, type, colon + 1)) {
            if(data)
                UA_delete(data, type);
            return false;
        }
        UA_Variant_setScalar(variant, data, type);
        return true;
    }

    for(const char *c = colon + 1; *c; c++)
        count += (*c == ',') ? 1 : 0;
    data = UA_Array_new(count, type);
    list = strdup(colon + 1);
    if(!data || !list) {
        UA_Array_delete(data, count, type);
        free(list);
        return false;
    }
    for(char *token = strtok_r(list, ",", &save); token && i < count;
        token = strtok_r(NULL, ",", &save), i++) {
        if(!parse_scalar((void *)((uintptr_t)data + i * type->memSize), type, token)) {
            UA_Array_delete(data, count, type);
            free(list);
            return false;
        }
    }
    free(list);
    UA_Variant_setArray(variant, data, count, type);
    return true;
}

static void
print_element(const void *data, const UA_DataType *type) {
    UA_String text = UA_STRING_NULL;

    if(UA_print(data, type, &text) == UA_STATUSCODE_GOOD)
        printf("%.*s", (int)text.length, (const char *)text.data);
    UA_String_clear(&text);
}

/* Prints a scalar as its text and an array as "[v1,v2,...]". */
static void
print_value(const UA_Variant *value) {
    if(!value->type || !value->data) {
        printf("<empty>");
        return;
    }
    if(UA_Variant_isScalar(value)) {
        print_element(value->data, value->type);
        return;
    }
    printf("[");
    for(size_t i = 0; i < value->arrayLength; i++) {
        if(i > 0)
            printf(",");
        print_element((const void *)((uintptr_t)value->data + i * value->type->memSize),
                      value->type);
    }
    printf("]");
}

static void
print_node_id(const UA_NodeId *id) {
    UA_String text = UA_STRING_NULL;

    if(UA_NodeId_print(id, &text) == UA_STATUSCODE_GOOD)
        printf("%.*s", (int)text.length, (const char *)text.data);
    UA_String_clear(&text);
}

/* Builds the client for the options: a session without security, with a user
 * name, or secured by the client certificate. The server certificate is
 * accepted without a trust list. */
static UA_Client *
new_client(const Options *options) {
    UA_ClientConfig config;

    memset(&config, 0, sizeof(config));
    config.logging = UA_Log_Stdout_new(UA_LOGLEVEL_FATAL);

    if(options->certificate && options->key) {
        UA_ByteString certificate = read_file(options->certificate);
        UA_ByteString key = read_file(options->key);
        size_t count = 0;
        UA_SecurityPolicy *policies = NULL;

        if(certificate.length == 0 || key.length == 0 ||
           UA_ClientConfig_setDefaultEncryption(&config, certificate, key, NULL, 0, NULL, 0) !=
               UA_STATUSCODE_GOOD) {
            UA_ByteString_clear(&certificate);
            UA_ByteString_clear(&key);
            return NULL;
        }

        /* The default set lacks the two older policies. */
        count = config.securityPoliciesSize;
        policies = (UA_SecurityPolicy *)UA_malloc((count + 2) * sizeof(UA_SecurityPolicy));
        if(!policies)
            return NULL;
        memcpy(policies, config.securityPolicies, count * sizeof(UA_SecurityPolicy));
        UA_free(config.securityPolicies);
        UA_SecurityPolicy_Basic128Rsa15(&policies[count], certificate, key, config.logging);
        UA_SecurityPolicy_Basic256(&policies[count + 1], certificate, key, config.logging);
        config.securityPolicies = policies;
        config.securityPoliciesSize = count + 2;

        UA_CertificateGroup_AcceptAll(&config.certificateVerification);
        UA_String_clear(&config.clientDescription.applicationUri);
        config.clientDescription.applicationUri = UA_STRING_ALLOC(CLIENT_URI);
        config.securityMode = (UA_MessageSecurityMode)options->mode;
        if(options->policy) {
            char uri[256];
            snprintf(uri, sizeof(uri), POLICY_URI_PREFIX "%s", options->policy);
            UA_String_clear(&config.securityPolicyUri);
            config.securityPolicyUri = UA_STRING_ALLOC(uri);
        }
        UA_ByteString_clear(&certificate);
        UA_ByteString_clear(&key);
    } else {
        UA_ClientConfig_setDefault(&config);
    }

    /* A user name is accepted on an endpoint without security, as the
     * simulated device does. */
    config.allowNonePolicyPassword = true;
    return UA_Client_newWithConfig(&config);
}

static int
command_read(UA_Client *client, const UA_NodeId *node) {
    UA_ReadValueId item;
    UA_DataValue result;

    UA_ReadValueId_init(&item);
    item.nodeId = *node;
    item.attributeId = UA_ATTRIBUTEID_VALUE;
    result = UA_Client_read(client, &item);
    printf("%s ", UA_StatusCode_name(result.hasStatus ? result.status : UA_STATUSCODE_GOOD));
    if(result.hasValue)
        print_value(&result.value);
    printf("\n");
    UA_DataValue_clear(&result);
    return 0;
}

static int
command_write(UA_Client *client, const UA_NodeId *node, char *type_name, const char *text) {
    size_t type_length = strlen(type_name);
    const UA_DataType *type = NULL;
    void *data = NULL;
    UA_Variant value;

    if(type_length > 2 && strcmp(type_name + type_length - 2, "[]") == 0) {
        size_t size = type_length + strlen(text) + 2;
        char *argument = (char *)malloc(size);
        UA_Boolean parsed = false;
        if(!argument)
            return EXIT_USAGE;
        snprintf(argument, size, "%s:%s", type_name, text);
        UA_Variant_init(&value);
        parsed = parse_argument(&value, argument);
        free(argument);
        if(!parsed)
            return EXIT_USAGE;
        printf("%s\n", UA_StatusCode_name(UA_Client_writeValueAttribute(client, *node, &value)));
        UA_Variant_clear(&value);
        return 0;
    }

    type = find_type(type_name);
    data = type ? UA_new(type) : NULL;
    if(!data || !parse_scalar(data, type, text)) {
        if(data)
            UA_delete(data, type);
        return EXIT_USAGE;
    }
    UA_Variant_setScalar(&value, data, type);
    printf("%s\n", UA_StatusCode_name(UA_Client_writeValueAttribute(client, *node, &value)));
    UA_Variant_clear(&value);
    return 0;
}

static int
command_call(UA_Client *client, const UA_NodeId *object, const char *method_text,
             int argc, char **argv) {
    UA_NodeId method = UA_NODEID_NULL;
    UA_Variant input[MAX_ARGUMENTS];
    UA_Variant *output = NULL;
    size_t output_size = 0;
    UA_StatusCode status = UA_STATUSCODE_GOOD;
    int result = 0;

    if(argc > MAX_ARGUMENTS || UA_NodeId_parse(&method, UA_STRING((char *)(uintptr_t)method_text)) !=
                                   UA_STATUSCODE_GOOD)
        return EXIT_USAGE;
    for(int i = 0; i < argc; i++) {
        UA_Variant_init(&input[i]);
        if(!parse_argument(&input[i], argv[i])) {
            for(int j = 0; j < i; j++)
                UA_Variant_clear(&input[j]);
            UA_NodeId_clear(&method);
            return EXIT_USAGE;
        }
    }

    status = UA_Client_call(client, *object, method, (size_t)argc, input, &output_size, &output);
    printf("%s\n", UA_StatusCode_name(status));
    for(size_t i = 0; i < output_size; i++) {
        printf("out ");
        print_value(&output[i]);
        printf("\n");
    }
    UA_Array_delete(output, output_size, &UA_TYPES[UA_TYPES_VARIANT]);
    for(int i = 0; i < argc; i++)
        UA_Variant_clear(&input[i]);
    UA_NodeId_clear(&method);
    return result;
}

static int
command_browse(UA_Client *client, const UA_NodeId *node, UA_Boolean all) {
    UA_BrowseRequest request;
    UA_BrowseDescription description;
    UA_BrowseResponse response;

    UA_BrowseRequest_init(&request);
    UA_BrowseDescription_init(&description);
    description.nodeId = *node;
    description.browseDirection = all ? UA_BROWSEDIRECTION_BOTH : UA_BROWSEDIRECTION_FORWARD;
    description.referenceTypeId =
        UA_NODEID_NUMERIC(0, all ? UA_NS0ID_REFERENCES : UA_NS0ID_HIERARCHICALREFERENCES);
    description.includeSubtypes = true;
    description.resultMask = UA_BROWSERESULTMASK_ALL;
    request.nodesToBrowse = &description;
    request.nodesToBrowseSize = 1;

    response = UA_Client_Service_browse(client, request);
    for(size_t r = 0; r < response.resultsSize; r++) {
        for(size_t k = 0; k < response.results[r].referencesSize; k++) {
            const UA_ReferenceDescription *ref = &response.results[r].references[k];
            if(all) {
                printf("%s ", ref->isForward ? "fwd" : "inv");
                print_node_id(&ref->referenceTypeId);
                printf(" ");
            }
            printf("%.*s ", (int)ref->browseName.name.length,
                   (const char *)ref->browseName.name.data);
            print_node_id(&ref->nodeId.nodeId);
            printf("\n");
        }
    }
    UA_BrowseResponse_clear(&response);
    return 0;
}

static int
command_endpoints(UA_Client *client, const char *url) {
    size_t size = 0;
    UA_EndpointDescription *endpoints = NULL;
    UA_StatusCode status = UA_Client_getEndpoints(client, url, &size, &endpoints);

    if(status != UA_STATUSCODE_GOOD) {
        printf("%s\n", UA_StatusCode_name(status));
        return 1;
    }
    for(size_t i = 0; i < size; i++) {
        const UA_String *policy = &endpoints[i].securityPolicyUri;
        size_t prefix = strlen(POLICY_URI_PREFIX);
        printf("mode %d policy %.*s\n", (int)endpoints[i].securityMode,
               (int)(policy->length > prefix ? policy->length - prefix : 0),
               (const char *)policy->data + (policy->length > prefix ? prefix : 0));
    }
    UA_Array_delete(endpoints, size, &UA_TYPES[UA_TYPES_ENDPOINTDESCRIPTION]);
    return 0;
}

/* Prints the fields of one event as "key=value" words. The select clauses
 * are in the order of the table in command_events. */
/* Extra fields that the events command prints, set by main. */
static char **extra_fields = NULL;
static int extra_field_count = 0;

/* The members of the union SimaticAssociatedAlarmValue in the order of the
 * model. The switch field of a value is the position of its member counted
 * from 1; the encoded value is the switch field as a UInt32 and then the
 * member. */
static const struct {
    const char *name;
    const UA_DataType *type;
} associated_members[] = {
    {"Invalid", &UA_TYPES[UA_TYPES_BOOLEAN]}, {"Boolean", &UA_TYPES[UA_TYPES_BOOLEAN]},
    {"Int16", &UA_TYPES[UA_TYPES_INT16]},     {"Int32", &UA_TYPES[UA_TYPES_INT32]},
    {"Int64", &UA_TYPES[UA_TYPES_INT64]},     {"SByte", &UA_TYPES[UA_TYPES_SBYTE]},
    {"Byte", &UA_TYPES[UA_TYPES_BYTE]},       {"UInt16", &UA_TYPES[UA_TYPES_UINT16]},
    {"UInt32", &UA_TYPES[UA_TYPES_UINT32]},   {"UInt64", &UA_TYPES[UA_TYPES_UINT64]},
    {"Float", &UA_TYPES[UA_TYPES_FLOAT]},     {"Double", &UA_TYPES[UA_TYPES_DOUBLE]},
    {"String", &UA_TYPES[UA_TYPES_STRING]}};

/* Prints a Float with the fewest digits that read back as the same Float, so
 * that 3.14 prints as 3.14 and not as the double that holds it. */
static void
print_float(UA_Float value) {
    char text[32];

    for(int digits = 1; digits <= 9; digits++) {
        snprintf(text, sizeof(text), "%.*g", digits, (double)value);
        if(strtof(text, NULL) == value)
            break;
    }
    printf("%s", text);
}

/* Prints an associated value from the encoded body of its ExtensionObject as
 * "<switch>:<member>:<value>", or as 0 when the switch field is 0. */
static void
print_associated_value(const UA_ByteString *body) {
    const size_t count = sizeof(associated_members) / sizeof(associated_members[0]);
    UA_UInt32 selection = 0;
    UA_ByteString payload = UA_BYTESTRING_NULL;
    const UA_DataType *type = NULL;
    void *value = NULL;

    if(body->length < 4) {
        printf("<invalid>");
        return;
    }
    selection = (UA_UInt32)body->data[0] | ((UA_UInt32)body->data[1] << 8) |
                ((UA_UInt32)body->data[2] << 16) | ((UA_UInt32)body->data[3] << 24);
    if(selection == 0) {
        printf("0");
        return;
    }
    if(selection > count) {
        printf("%u:unknown", (unsigned)selection);
        return;
    }
    printf("%u:%s:", (unsigned)selection, associated_members[selection - 1].name);
    type = associated_members[selection - 1].type;
    payload.length = body->length - 4;
    payload.data = body->data + 4;
    value = UA_new(type);
    if(value && UA_decodeBinary(&payload, value, type, NULL) == UA_STATUSCODE_GOOD) {
        if(type == &UA_TYPES[UA_TYPES_STRING])
            printf("%.*s", (int)((const UA_String *)value)->length,
                   (const char *)((const UA_String *)value)->data);
        else if(type == &UA_TYPES[UA_TYPES_FLOAT])
            print_float(*(const UA_Float *)value);
        else if(type == &UA_TYPES[UA_TYPES_INT64])
            printf("%lld", (long long)*(const UA_Int64 *)value);
        else if(type == &UA_TYPES[UA_TYPES_UINT64])
            printf("%llu", (unsigned long long)*(const UA_UInt64 *)value);
        else
            print_element(value, type);
    } else {
        printf("<invalid>");
    }
    if(value)
        UA_delete(value, type);
}

/* Prints a LocalizedText as its text and any other value as UA_print does. */
static void
print_field_value(const UA_Variant *v) {
    if(UA_Variant_hasScalarType(v, &UA_TYPES[UA_TYPES_LOCALIZEDTEXT])) {
        const UA_LocalizedText *text = (const UA_LocalizedText *)v->data;
        printf("%.*s", (int)text->text.length, (const char *)text->text.data);
    } else {
        print_element(v->data, v->type);
    }
}

static void
on_event(UA_Client *client, UA_UInt32 subscription, void *subscription_context,
         UA_UInt32 monitored_item, void *monitored_item_context,
         const UA_KeyValueMap fields) {
    const UA_Variant *v = NULL;

    (void)client;
    (void)subscription;
    (void)subscription_context;
    (void)monitored_item;
    (void)monitored_item_context;
    if(fields.mapSize < EVENT_BASE_FIELDS + 2 * (size_t)extra_field_count)
        return;

    printf("event");
    v = &fields.map[0].value;
    if(UA_Variant_hasScalarType(v, &UA_TYPES[UA_TYPES_NODEID])) {
        printf(" type=");
        print_node_id((const UA_NodeId *)v->data);
    }
    v = &fields.map[1].value;
    if(UA_Variant_hasScalarType(v, &UA_TYPES[UA_TYPES_LOCALIZEDTEXT]))
        printf(" message=\"%.*s\"", (int)((const UA_LocalizedText *)v->data)->text.length,
               (const char *)((const UA_LocalizedText *)v->data)->text.data);
    v = &fields.map[2].value;
    if(UA_Variant_hasScalarType(v, &UA_TYPES[UA_TYPES_UINT16]))
        printf(" severity=%u", *(const UA_UInt16 *)v->data);
    v = &fields.map[3].value;
    if(UA_Variant_hasScalarType(v, &UA_TYPES[UA_TYPES_STRING]))
        printf(" source=%.*s", (int)((const UA_String *)v->data)->length,
               (const char *)((const UA_String *)v->data)->data);
    static const char *const flags[] = {"active", "acked", "retain"};
    for(size_t i = 0; i < 3; i++) {
        v = &fields.map[4 + i].value;
        if(UA_Variant_hasScalarType(v, &UA_TYPES[UA_TYPES_BOOLEAN]))
            printf(" %s=%d", flags[i], *(const UA_Boolean *)v->data ? 1 : 0);
    }
    v = &fields.map[7].value;
    if(UA_Variant_hasScalarType(v, &UA_TYPES[UA_TYPES_BYTESTRING])) {
        const UA_ByteString *id = (const UA_ByteString *)v->data;
        printf(" eventid=");
        for(size_t i = 0; i < id->length; i++)
            printf("%02x", id->data[i]);
    }
    v = &fields.map[8].value;
    if(UA_Variant_hasScalarType(v, &UA_TYPES[UA_TYPES_NODEID])) {
        printf(" condition=");
        print_node_id((const UA_NodeId *)v->data);
    }
    for(int i = 0; i < extra_field_count; i++) {
        for(int k = 0; k < 2; k++) {
            v = &fields.map[EVENT_BASE_FIELDS + 2 * i + k].value;
            if(v->type && v->data && UA_Variant_isScalar(v)) {
                printf(" %s=", extra_fields[i]);
                if(strncmp(extra_fields[i], "AssociatedValue_", 16) == 0 &&
                   UA_Variant_hasScalarType(v, &UA_TYPES[UA_TYPES_EXTENSIONOBJECT]) &&
                   ((const UA_ExtensionObject *)v->data)->encoding ==
                       UA_EXTENSIONOBJECT_ENCODED_BYTESTRING)
                    print_associated_value(&((const UA_ExtensionObject *)v->data)->content.encoded.body);
                else
                    print_field_value(v);
                break;
            }
        }
    }
    printf("\n");
    fflush(stdout);
}

static int
command_events(UA_Client *client, const UA_NodeId *node, const char *seconds_text,
               int field_count, char **field_names) {
    /* Each field is selected through the type that declares it: the server
     * rejects a filter that names a field of a subtype through its supertype. */
    static const struct {
        UA_UInt32 type;
        const char *path[2];
        UA_UInt32 attribute;
    } fields[] = {
        {UA_NS0ID_BASEEVENTTYPE, {"EventType", NULL}, UA_ATTRIBUTEID_VALUE},
        {UA_NS0ID_BASEEVENTTYPE, {"Message", NULL}, UA_ATTRIBUTEID_VALUE},
        {UA_NS0ID_BASEEVENTTYPE, {"Severity", NULL}, UA_ATTRIBUTEID_VALUE},
        {UA_NS0ID_BASEEVENTTYPE, {"SourceName", NULL}, UA_ATTRIBUTEID_VALUE},
        {UA_NS0ID_ALARMCONDITIONTYPE, {"ActiveState", "Id"}, UA_ATTRIBUTEID_VALUE},
        {UA_NS0ID_ACKNOWLEDGEABLECONDITIONTYPE, {"AckedState", "Id"}, UA_ATTRIBUTEID_VALUE},
        {UA_NS0ID_CONDITIONTYPE, {"Retain", NULL}, UA_ATTRIBUTEID_VALUE},
        {UA_NS0ID_BASEEVENTTYPE, {"EventId", NULL}, UA_ATTRIBUTEID_VALUE},
        {UA_NS0ID_CONDITIONTYPE, {NULL, NULL}, UA_ATTRIBUTEID_NODEID},
    };
    enum { FIELD_COUNT = sizeof(fields) / sizeof(fields[0]),
           CLAUSE_COUNT = FIELD_COUNT + 2 * MAX_EVENT_FIELDS };
    UA_SimpleAttributeOperand select[CLAUSE_COUNT];
    UA_QualifiedName names[CLAUSE_COUNT][2];
    UA_EventFilter filter;
    UA_MonitoredItemCreateRequest item;
    UA_MonitoredItemCreateResult created;
    UA_CreateSubscriptionResponse subscription;
    long seconds = strtol(seconds_text, NULL, 10);
    time_t end = 0;

    if(field_count > MAX_EVENT_FIELDS)
        return EXIT_USAGE;
    extra_fields = field_names;
    extra_field_count = field_count;
    for(size_t i = 0; i < FIELD_COUNT; i++) {
        size_t depth = 0;
        UA_SimpleAttributeOperand_init(&select[i]);
        select[i].typeDefinitionId = UA_NODEID_NUMERIC(0, fields[i].type);
        select[i].attributeId = fields[i].attribute;
        for(size_t k = 0; k < 2; k++) {
            if(fields[i].path[k])
                names[i][depth++] = UA_QUALIFIEDNAME(0, (char *)(uintptr_t)fields[i].path[k]);
        }
        select[i].browsePath = names[i];
        select[i].browsePathSize = depth;
    }
    /* An extra field is selected through both Simatic types, one clause each:
     * the alarm type is no subtype of the event type. */
    for(int i = 0; i < field_count; i++) {
        for(int k = 0; k < 2; k++) {
            size_t at = FIELD_COUNT + 2 * (size_t)i + (size_t)k;
            UA_SimpleAttributeOperand_init(&select[at]);
            select[at].typeDefinitionId = UA_NODEID_NUMERIC(SIMATIC_NAMESPACE,
                k == 0 ? SIMATIC_EVENT_TYPE : SIMATIC_ALARM_TYPE);
            select[at].attributeId = UA_ATTRIBUTEID_VALUE;
            names[at][0] = UA_QUALIFIEDNAME(SIMATIC_NAMESPACE, field_names[i]);
            select[at].browsePath = names[at];
            select[at].browsePathSize = 1;
        }
    }
    UA_EventFilter_init(&filter);
    filter.selectClauses = select;
    filter.selectClausesSize = FIELD_COUNT + 2 * (size_t)field_count;

    subscription = UA_Client_Subscriptions_create(client, UA_CreateSubscriptionRequest_default(),
                                                  NULL, NULL, NULL);
    UA_MonitoredItemCreateRequest_init(&item);
    item.itemToMonitor.nodeId = *node;
    item.itemToMonitor.attributeId = UA_ATTRIBUTEID_EVENTNOTIFIER;
    item.monitoringMode = UA_MONITORINGMODE_REPORTING;
    item.requestedParameters.queueSize = EVENT_QUEUE_SIZE;
    UA_ExtensionObject_setValue(&item.requestedParameters.filter, &filter,
                                &UA_TYPES[UA_TYPES_EVENTFILTER]);
    created = UA_Client_MonitoredItems_createEvent(client, subscription.subscriptionId,
                                                   UA_TIMESTAMPSTORETURN_BOTH, item, NULL,
                                                   on_event, NULL);
    printf("monitor %s\n", UA_StatusCode_name(created.statusCode));
    fflush(stdout);

    end = time(NULL) + seconds;
    while(time(NULL) < end)
        UA_Client_run_iterate(client, EVENT_STEP_MS);
    return 0;
}

/* Opens a session with the credentials and security settings of the options.
 * Returns NULL and the status when it fails. */
static UA_Client *
open_session(const Options *options, const char *url, UA_StatusCode *status) {
    UA_Client *client = new_client(options);

    if(!client) {
        *status = UA_STATUSCODE_BADCONFIGURATIONERROR;
        return NULL;
    }
    *status = options->user ? UA_Client_connectUsername(client, url, options->user,
                                                        options->password ? options->password : "")
                            : UA_Client_connect(client, url);
    if(*status != UA_STATUSCODE_GOOD) {
        UA_Client_delete(client);
        return NULL;
    }
    return client;
}

/* Does nothing with a value; the commands below create monitored items only
 * to see what the server answers. */
static void
ignore_data_change(UA_Client *client, UA_UInt32 subscription, void *subscription_context,
                   UA_UInt32 monitored_item, void *monitored_item_context,
                   UA_DataValue *value) {
    (void)client;
    (void)subscription;
    (void)subscription_context;
    (void)monitored_item;
    (void)monitored_item_context;
    (void)value;
}

/* A subscription with a publishing interval of 1 ms and an item on the node
 * with a sampling interval of 1 ms: the server revises both to its minimum. The
 * revised sampling interval is also at least the MinimumSamplingInterval of
 * the node. */
static int
command_intervals(UA_Client *client, const UA_NodeId *node) {
    UA_CreateSubscriptionRequest request = UA_CreateSubscriptionRequest_default();
    UA_CreateSubscriptionResponse subscription;
    UA_MonitoredItemCreateRequest item;
    UA_MonitoredItemCreateResult created;

    request.requestedPublishingInterval = 1.0;
    subscription = UA_Client_Subscriptions_create(client, request, NULL, NULL, NULL);
    if(subscription.responseHeader.serviceResult != UA_STATUSCODE_GOOD) {
        printf("%s\n", UA_StatusCode_name(subscription.responseHeader.serviceResult));
        return 0;
    }
    item = UA_MonitoredItemCreateRequest_default(*node);
    item.requestedParameters.samplingInterval = 1.0;
    created = UA_Client_MonitoredItems_createDataChange(
        client, subscription.subscriptionId, UA_TIMESTAMPSTORETURN_BOTH, item, NULL,
        ignore_data_change, NULL);
    if(created.statusCode != UA_STATUSCODE_GOOD)
        printf("%s\n", UA_StatusCode_name(created.statusCode));
    else
        printf("Good publishing=%g sampling=%g\n", subscription.revisedPublishingInterval,
               created.revisedSamplingInterval);
    return 0;
}

/* Opens sessions, the session of this probe included, until the server refuses
 * one. The count of open sessions is read while all of them are open. */
static int
command_sessions(UA_Client *client, const Options *options, const char *url) {
    UA_Client *held[MAX_SESSIONS_TRIED];
    UA_StatusCode refused = UA_STATUSCODE_GOOD;
    UA_UInt32 current = 0;
    UA_Variant value;
    size_t accepted = 1;

    while(accepted < MAX_SESSIONS_TRIED && refused == UA_STATUSCODE_GOOD) {
        held[accepted - 1] = open_session(options, url, &refused);
        if(held[accepted - 1])
            accepted++;
    }
    UA_Variant_init(&value);
    if(UA_Client_readValueAttribute(
           client, UA_NODEID_NUMERIC(0, UA_NS0ID_SERVER_SERVERDIAGNOSTICS_SERVERDIAGNOSTICSSUMMARY_CURRENTSESSIONCOUNT),
           &value) == UA_STATUSCODE_GOOD &&
       UA_Variant_hasScalarType(&value, &UA_TYPES[UA_TYPES_UINT32]))
        current = *(const UA_UInt32 *)value.data;
    UA_Variant_clear(&value);
    printf("Good accepted=%lu refused=%s current=%lu\n", (unsigned long)accepted,
           UA_StatusCode_name(refused), (unsigned long)current);
    for(size_t i = 0; i + 1 < accepted; i++)
        UA_Client_delete(held[i]);
    return 0;
}

/* Creates up to count subscriptions in this session. */
static int
command_subscriptions(UA_Client *client, long count) {
    UA_StatusCode refused = UA_STATUSCODE_GOOD;
    long created = 0;

    while(created < count && refused == UA_STATUSCODE_GOOD) {
        UA_CreateSubscriptionResponse response = UA_Client_Subscriptions_create(
            client, UA_CreateSubscriptionRequest_default(), NULL, NULL, NULL);
        refused = response.responseHeader.serviceResult;
        if(refused == UA_STATUSCODE_GOOD)
            created++;
    }
    printf("Good created=%ld refused=%s\n", created, UA_StatusCode_name(refused));
    return 0;
}

/* Creates count monitored items on CurrentTime in one subscription, in calls
 * of ITEMS_PER_CALL items, and stops at the first refused item. */
static int
command_items(UA_Client *client, long count) {
    UA_CreateSubscriptionResponse subscription = UA_Client_Subscriptions_create(
        client, UA_CreateSubscriptionRequest_default(), NULL, NULL, NULL);
    UA_StatusCode refused = subscription.responseHeader.serviceResult;
    long created = 0;

    while(created < count && refused == UA_STATUSCODE_GOOD) {
        UA_MonitoredItemCreateRequest items[ITEMS_PER_CALL];
        void *contexts[ITEMS_PER_CALL];
        UA_Client_DataChangeNotificationCallback callbacks[ITEMS_PER_CALL];
        UA_Client_DeleteMonitoredItemCallback deletes[ITEMS_PER_CALL];
        UA_CreateMonitoredItemsRequest request;
        UA_CreateMonitoredItemsResponse response;
        long batch = count - created < ITEMS_PER_CALL ? count - created : ITEMS_PER_CALL;

        for(long i = 0; i < batch; i++) {
            items[i] = UA_MonitoredItemCreateRequest_default(
                UA_NODEID_NUMERIC(0, UA_NS0ID_SERVER_SERVERSTATUS_CURRENTTIME));
            items[i].requestedParameters.samplingInterval = ITEM_SAMPLING_MS;
            contexts[i] = NULL;
            callbacks[i] = ignore_data_change;
            deletes[i] = NULL;
        }
        UA_CreateMonitoredItemsRequest_init(&request);
        request.subscriptionId = subscription.subscriptionId;
        request.timestampsToReturn = UA_TIMESTAMPSTORETURN_BOTH;
        request.itemsToCreate = items;
        request.itemsToCreateSize = (size_t)batch;
        response = UA_Client_MonitoredItems_createDataChanges(client, request, contexts,
                                                              callbacks, deletes);
        refused = response.responseHeader.serviceResult;
        for(size_t i = 0; refused == UA_STATUSCODE_GOOD && i < response.resultsSize; i++) {
            if(response.results[i].statusCode == UA_STATUSCODE_GOOD)
                created++;
            else if(refused == UA_STATUSCODE_GOOD)
                refused = response.results[i].statusCode;
        }
        UA_CreateMonitoredItemsResponse_clear(&response);
    }
    printf("Good created=%ld refused=%s\n", created, UA_StatusCode_name(refused));
    return 0;
}

int
main(int argc, char **argv) {
    Options options = {NULL, NULL, NULL, NULL, NULL, 3};
    UA_Client *client = NULL;
    UA_StatusCode status = UA_STATUSCODE_GOOD;
    UA_NodeId node = UA_NODEID_NULL;
    const char *url = NULL;
    const char *command = NULL;
    char **rest = NULL;
    int rest_size = 0;
    int option = 0;
    int result = EXIT_USAGE;

    while((option = getopt(argc, argv, "u:p:c:k:P:m:")) != -1) {
        if(option == 'u')
            options.user = optarg;
        else if(option == 'p')
            options.password = optarg;
        else if(option == 'c')
            options.certificate = optarg;
        else if(option == 'k')
            options.key = optarg;
        else if(option == 'P')
            options.policy = optarg;
        else if(option == 'm')
            options.mode = atoi(optarg);
        else
            return EXIT_USAGE;
    }
    if(argc - optind < 2) {
        fprintf(stderr, "usage: %s [options] <endpoint-url> <command> [arguments]\n", argv[0]);
        return EXIT_USAGE;
    }
    url = argv[optind];
    command = argv[optind + 1];
    rest = argv + optind + 2;
    rest_size = argc - optind - 2;

    client = open_session(&options, url, &status);
    if(!client) {
        printf("connect %s\n", UA_StatusCode_name(status));
        return 1;
    }

    if(rest_size >= 1 && strcmp(command, "endpoints") != 0 &&
       strcmp(command, "subscriptions") != 0 && strcmp(command, "items") != 0 &&
       UA_NodeId_parse(&node, UA_STRING(rest[0])) != UA_STATUSCODE_GOOD) {
        fprintf(stderr, "bad node id %s\n", rest[0]);
    } else if(strcmp(command, "read") == 0 && rest_size == 1) {
        result = command_read(client, &node);
    } else if(strcmp(command, "write") == 0 && rest_size == 3) {
        result = command_write(client, &node, rest[1], rest[2]);
    } else if(strcmp(command, "call") == 0 && rest_size >= 2) {
        result = command_call(client, &node, rest[1], rest_size - 2, rest + 2);
    } else if(strcmp(command, "browse") == 0 && rest_size == 1) {
        result = command_browse(client, &node, false);
    } else if(strcmp(command, "refs") == 0 && rest_size == 1) {
        result = command_browse(client, &node, true);
    } else if(strcmp(command, "endpoints") == 0 && rest_size == 0) {
        result = command_endpoints(client, url);
    } else if(strcmp(command, "events") == 0 && rest_size >= 2) {
        result = command_events(client, &node, rest[1], rest_size - 2, rest + 2);
    } else if(strcmp(command, "intervals") == 0 && rest_size <= 1) {
        UA_NodeId current_time = UA_NODEID_NUMERIC(0, UA_NS0ID_SERVER_SERVERSTATUS_CURRENTTIME);
        result = command_intervals(client, rest_size == 1 ? &node : &current_time);
    } else if(strcmp(command, "sessions") == 0 && rest_size == 0) {
        result = command_sessions(client, &options, url);
    } else if(strcmp(command, "subscriptions") == 0 && rest_size == 1 && atol(rest[0]) > 0) {
        result = command_subscriptions(client, atol(rest[0]));
    } else if(strcmp(command, "items") == 0 && rest_size == 1 && atol(rest[0]) > 0) {
        result = command_items(client, atol(rest[0]));
    } else {
        fprintf(stderr, "unknown command or wrong arguments: %s\n", command);
    }

    UA_NodeId_clear(&node);
    UA_Client_delete(client);
    return result;
}
