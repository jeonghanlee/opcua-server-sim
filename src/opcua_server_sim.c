/*
 * Generic OPC UA server simulator.
 *
 * The server holds no device knowledge. The server configuration comes from
 * an open62541 JSON configuration file and the information model from
 * NodeSet2 XML files, loaded in command-line order. The load order fixes the
 * namespace indices. An optional simulation file describes the behavior: the
 * Variables whose values change over time with the signal each one follows,
 * the logic elements that combine Variables (pack, count, on-delay), the
 * alarms and events that follow a Boolean Variable, the Methods the server
 * answers, the operating state of the simulated CPU, and the user accounts.
 * The build system sets the build number, the version, and the build date
 * that the Server object reports.
 */

#include <open62541/plugin/accesscontrol_default.h>
#include <open62541/plugin/log_stdout.h>
#include <open62541/plugin/nodesetloader.h>
#include <open62541/server.h>
#include <open62541/server_config_file_based.h>

#include <errno.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define EXIT_USAGE 2

/* Defaults of the simulation file: the interval between simulation steps and
 * the parameters a signal line leaves out. */
#define SIM_DEFAULT_CYCLE_MS 100.0
#define SIM_DEFAULT_MIN 0.0
#define SIM_DEFAULT_MAX 100.0
#define SIM_DEFAULT_STEP 1.0
#define SIM_DEFAULT_PERIOD_MS 1000.0
#define SIM_TWO_PI 6.283185307179586

/* Namespace and names of the nodes that operate the simulator itself, and
 * the locale of the alarm messages. */
#define SIM_CONTROL_NAMESPACE "urn:opcua-server-sim:control"
#define SIM_CONTROL_OBJECT "Simulator"
#define SIM_CONTROL_SWITCH "Run"
#define SIM_CONTROL_SWITCH_ID SIM_CONTROL_OBJECT "." SIM_CONTROL_SWITCH
#define SIM_LOCALE "en-US"

/* Identity of the build, set by the build system: the commit of the source
 * tree, the version derived from its tags, and the time of the compilation in
 * seconds since 1970 (UTC). */
#ifndef SIM_BUILD_NUMBER
#define SIM_BUILD_NUMBER "unknown"
#endif
#ifndef SIM_SOFTWARE_VERSION
#define SIM_SOFTWARE_VERSION "unknown"
#endif
#ifndef SIM_BUILD_TIME
#define SIM_BUILD_TIME 0
#endif

/* Reads a whole file into a byte string. Returns an empty byte string and
 * logs the reason when the file cannot be read. */
static UA_ByteString
read_file(const char *path) {
    UA_ByteString content = UA_BYTESTRING_NULL;
    FILE *fp = fopen(path, "rb");
    long size = 0;

    if(!fp) {
        UA_LOG_FATAL(UA_Log_Stdout, UA_LOGCATEGORY_APPLICATION,
                     "cannot open %s: %s", path, strerror(errno));
        return content;
    }

    if(fseek(fp, 0, SEEK_END) != 0 || (size = ftell(fp)) < 0 ||
       fseek(fp, 0, SEEK_SET) != 0) {
        UA_LOG_FATAL(UA_Log_Stdout, UA_LOGCATEGORY_APPLICATION,
                     "cannot determine the size of %s: %s", path, strerror(errno));
        fclose(fp);
        return content;
    }

    if(UA_ByteString_allocBuffer(&content, (size_t)size) != UA_STATUSCODE_GOOD) {
        UA_LOG_FATAL(UA_Log_Stdout, UA_LOGCATEGORY_APPLICATION,
                     "cannot allocate %ld bytes for %s", size, path);
        fclose(fp);
        return content;
    }

    if(fread(content.data, 1, content.length, fp) != content.length) {
        UA_LOG_FATAL(UA_Log_Stdout, UA_LOGCATEGORY_APPLICATION,
                     "cannot read %s", path);
        UA_ByteString_clear(&content);
    }

    fclose(fp);
    return content;
}

/* Puts the identity of this build into the BuildInfo of the Server object.
 * The product and the manufacturer come from the server configuration file. */
static void
set_build_identity(UA_Server *server) {
    UA_BuildInfo *info = &UA_Server_getConfig(server)->buildInfo;

    UA_String_clear(&info->buildNumber);
    info->buildNumber = UA_STRING_ALLOC(SIM_BUILD_NUMBER);
    UA_String_clear(&info->softwareVersion);
    info->softwareVersion = UA_STRING_ALLOC(SIM_SOFTWARE_VERSION);
    info->buildDate = UA_DateTime_fromUnixTime((UA_Int64)SIM_BUILD_TIME);
}

/* Logs the namespace table so the indices assigned by the load order are
 * visible at start. */
static void
log_namespaces(UA_Server *server) {
    UA_Variant value;
    UA_Variant_init(&value);

    if(UA_Server_readValue(server,
                           UA_NODEID_NUMERIC(0, UA_NS0ID_SERVER_NAMESPACEARRAY),
                           &value) != UA_STATUSCODE_GOOD)
        return;

    if(UA_Variant_hasArrayType(&value, &UA_TYPES[UA_TYPES_STRING])) {
        const UA_String *uris = (const UA_String *)value.data;
        for(size_t i = 0; i < value.arrayLength; i++)
            UA_LOG_INFO(UA_Log_Stdout, UA_LOGCATEGORY_APPLICATION,
                        "namespace %lu: %.*s", (unsigned long)i,
                        (int)uris[i].length, (const char *)uris[i].data);
    }

    UA_Variant_clear(&value);
}

/* A Variable whose value is one slot of its parent Variable: an element of
 * the parent array or a member of the parent structure. */
typedef enum { LINK_ELEMENT, LINK_MEMBER } LinkKind;

typedef struct {
    UA_NodeId parent;
    UA_NodeId child;
    LinkKind kind;
    size_t slot;
} ValueLink;

/* Links between parent and child values, and the guard that keeps a
 * propagated write from starting another propagation. */
static ValueLink *value_links = NULL;
static size_t value_links_size = 0;
static UA_Boolean propagating = false;

/* Returns the declared element count of a Variable, or 0 when the Variable
 * is a scalar or has no fixed array dimensions. */
static size_t
declared_array_length(UA_Server *server, const UA_NodeId *id) {
    UA_Variant dims;
    size_t count = 1;

    UA_Variant_init(&dims);
    if(UA_Server_readArrayDimensions(server, *id, &dims) != UA_STATUSCODE_GOOD)
        return 0;

    if(!UA_Variant_hasArrayType(&dims, &UA_TYPES[UA_TYPES_UINT32]) ||
       dims.arrayLength == 0)
        count = 0;
    for(size_t i = 0; count > 0 && i < dims.arrayLength; i++)
        count *= ((const UA_UInt32 *)dims.data)[i];

    UA_Variant_clear(&dims);
    return count;
}

/* Two data types hold interchangeable values when their kind and in-memory
 * size agree; a NodeSet may name a subtype of a builtin type in one place and
 * the builtin type in another. */
static UA_Boolean
same_layout(const UA_DataType *a, const UA_DataType *b) {
    return a && b && a->typeKind == b->typeKind && a->memSize == b->memSize;
}

/* Gives one Variable a zero-initialized value of its declared data type and
 * size. A NodeSet without values leaves a Variable empty, a structure with
 * the placeholder value of its abstract supertype, and an array without
 * elements, while a device reports typed values of the declared size.
 * Variables that hold a value of their declared type keep it. */
static void
init_value(UA_Server *server, const UA_NodeId *id) {
    UA_NodeId data_type_id = UA_NODEID_NULL;
    const UA_DataType *type = NULL;
    UA_Variant value;
    UA_Variant filled;
    UA_Int32 rank = UA_VALUERANK_SCALAR;
    size_t count = 0;
    UA_Boolean untyped = false;
    UA_Boolean empty_array = false;

    UA_Variant_init(&value);
    UA_Variant_init(&filled);

    if(UA_Server_readDataType(server, *id, &data_type_id) != UA_STATUSCODE_GOOD)
        return;
    type = UA_Server_findDataType(server, &data_type_id);
    UA_NodeId_clear(&data_type_id);
    if(!type || UA_Server_readValueRank(server, *id, &rank) != UA_STATUSCODE_GOOD ||
       UA_Server_readValue(server, *id, &value) != UA_STATUSCODE_GOOD)
        return;

    count = (rank >= UA_VALUERANK_ONE_DIMENSION) ? declared_array_length(server, id) : 0;
    untyped = !value.type ||
              (type->typeKind == UA_DATATYPEKIND_STRUCTURE &&
               !same_layout(value.type, type));
    empty_array = count > 0 && !UA_Variant_isScalar(&value) && value.arrayLength == 0;
    if(!untyped && !empty_array)
        goto cleanup;
    if(!untyped)
        type = value.type;

    if(rank < UA_VALUERANK_ONE_DIMENSION) {
        filled.data = UA_new(type);
    } else if(count > 0) {
        filled.data = UA_Array_new(count, type);
        filled.arrayLength = count;
    } else {
        goto cleanup;
    }
    if(!filled.data)
        goto cleanup;
    filled.type = type;

    if(UA_Server_writeValue(server, *id, filled) != UA_STATUSCODE_GOOD)
        UA_LOG_WARNING(UA_Log_Stdout, UA_LOGCATEGORY_APPLICATION,
                       "cannot initialize the value of %N", *id);

cleanup:
    UA_Variant_clear(&value);
    UA_Variant_clear(&filled);
}

/* Locates the slot a link names inside the parent value. Reports the slot
 * address and type, and for an array member the element count. Returns false
 * when the parent value does not hold that slot. */
static UA_Boolean
find_slot(const UA_Variant *parent, const ValueLink *link, void **slot,
          const UA_DataType **slot_type, UA_Boolean *slot_is_array) {
    uintptr_t ptr = 0;

    if(!parent->type || !parent->data)
        return false;

    if(link->kind == LINK_ELEMENT) {
        if(UA_Variant_isScalar(parent) || link->slot >= parent->arrayLength)
            return false;
        *slot = (void *)((uintptr_t)parent->data + link->slot * parent->type->memSize);
        *slot_type = parent->type;
        *slot_is_array = false;
        return true;
    }

    if(!UA_Variant_isScalar(parent) ||
       parent->type->typeKind != UA_DATATYPEKIND_STRUCTURE ||
       link->slot >= parent->type->membersSize)
        return false;

    ptr = (uintptr_t)parent->data;
    for(size_t i = 0; i <= link->slot; i++) {
        const UA_DataTypeMember *member = &parent->type->members[i];
        if(member->isOptional)
            return false;
        ptr += member->padding;
        if(i == link->slot) {
            *slot = (void *)ptr;
            *slot_type = member->memberType;
            *slot_is_array = member->isArray;
            return true;
        }
        ptr += member->isArray ? sizeof(size_t) + sizeof(void *)
                               : member->memberType->memSize;
    }
    return false;
}

/* Writes the slot of the parent value into the child Variable. */
static void
copy_down(UA_Server *server, const ValueLink *link) {
    UA_Variant parent;
    UA_Variant child;
    UA_Variant out;
    void *slot = NULL;
    const UA_DataType *slot_type = NULL;
    UA_Boolean slot_is_array = false;

    UA_Variant_init(&parent);
    UA_Variant_init(&child);
    UA_Variant_init(&out);

    if(UA_Server_readValue(server, link->parent, &parent) != UA_STATUSCODE_GOOD ||
       UA_Server_readValue(server, link->child, &child) != UA_STATUSCODE_GOOD ||
       !find_slot(&parent, link, &slot, &slot_type, &slot_is_array) ||
       !same_layout(child.type, slot_type))
        goto cleanup;

    /* The out variant borrows the slot memory; the write copies it. */
    out.type = child.type;
    out.storageType = UA_VARIANT_DATA_NODELETE;
    if(slot_is_array) {
        out.arrayLength = *(size_t *)slot;
        out.data = *(void **)((uintptr_t)slot + sizeof(size_t));
        if(out.arrayLength == 0)
            out.data = UA_EMPTY_ARRAY_SENTINEL;
    } else {
        out.data = slot;
    }
    UA_Server_writeValue(server, link->child, out);

cleanup:
    UA_Variant_clear(&parent);
    UA_Variant_clear(&child);
}

/* Writes the child value into its slot of the parent Variable. */
static void
copy_up(UA_Server *server, const ValueLink *link) {
    UA_Variant parent;
    UA_Variant child;
    void *slot = NULL;
    const UA_DataType *slot_type = NULL;
    UA_Boolean slot_is_array = false;

    UA_Variant_init(&parent);
    UA_Variant_init(&child);

    if(UA_Server_readValue(server, link->parent, &parent) != UA_STATUSCODE_GOOD ||
       UA_Server_readValue(server, link->child, &child) != UA_STATUSCODE_GOOD ||
       !find_slot(&parent, link, &slot, &slot_type, &slot_is_array) ||
       !same_layout(child.type, slot_type) || !child.data ||
       slot_is_array == UA_Variant_isScalar(&child))
        goto cleanup;

    if(slot_is_array) {
        size_t *length = (size_t *)slot;
        void **data = (void **)((uintptr_t)slot + sizeof(size_t));
        UA_Array_delete(*data, *length, slot_type);
        *length = 0;
        *data = NULL;
        if(UA_Array_copy(child.data, child.arrayLength, data, slot_type) ==
           UA_STATUSCODE_GOOD)
            *length = child.arrayLength;
    } else {
        UA_clear(slot, slot_type);
        UA_copy(child.data, slot, slot_type);
    }
    UA_Server_writeValue(server, link->parent, parent);

cleanup:
    UA_Variant_clear(&parent);
    UA_Variant_clear(&child);
}

/* Carries the value of a Variable into all Variables below it. */
static void
propagate_down(UA_Server *server, const UA_NodeId *id) {
    for(size_t i = 0; i < value_links_size; i++) {
        if(!UA_NodeId_equal(&value_links[i].parent, id))
            continue;
        copy_down(server, &value_links[i]);
        propagate_down(server, &value_links[i].child);
    }
}

/* Carries the value of a Variable into all Variables above it. */
static void
propagate_up(UA_Server *server, const UA_NodeId *id) {
    for(size_t i = 0; i < value_links_size; i++) {
        if(!UA_NodeId_equal(&value_links[i].child, id))
            continue;
        copy_up(server, &value_links[i]);
        propagate_up(server, &value_links[i].parent);
    }
}

/* Keeps linked Variables consistent after a write: an array and its element
 * Variables, a structure and its member Variables, share one value as they
 * share memory in a device. */
static void
on_linked_write(UA_Server *server, const UA_NodeId *session_id,
                void *session_context, const UA_NodeId *node_id,
                void *node_context, const UA_NumericRange *range,
                const UA_DataValue *data) {
    (void)session_id;
    (void)session_context;
    (void)node_context;
    (void)range;
    (void)data;

    if(propagating)
        return;
    propagating = true;
    propagate_down(server, node_id);
    propagate_up(server, node_id);
    propagating = false;
}

/* Determines which slot of the parent value a child Variable represents,
 * from the child browse name: a decimal index for an array element, a member
 * name for a structure member. */
static UA_Boolean
resolve_slot(const UA_Variant *parent, const UA_String *name, ValueLink *link) {
    if(!parent->type || name->length == 0)
        return false;

    if(!UA_Variant_isScalar(parent)) {
        size_t index = 0;
        for(size_t i = 0; i < name->length; i++) {
            if(name->data[i] < '0' || name->data[i] > '9')
                return false;
            index = index * 10 + (size_t)(name->data[i] - '0');
        }
        if(index >= parent->arrayLength)
            return false;
        link->kind = LINK_ELEMENT;
        link->slot = index;
        return true;
    }

    if(parent->type->typeKind != UA_DATATYPEKIND_STRUCTURE)
        return false;
    for(size_t i = 0; i < parent->type->membersSize; i++) {
        const char *member_name = parent->type->members[i].memberName;
        if(member_name && strlen(member_name) == name->length &&
           memcmp(member_name, name->data, name->length) == 0) {
            link->kind = LINK_MEMBER;
            link->slot = i;
            return true;
        }
    }
    return false;
}

/* Records the links from one Variable to its component Variables and
 * registers the write notification on both ends of every link. */
static void
link_children(UA_Server *server, const UA_NodeId *parent_id) {
    static const UA_ValueSourceNotifications notifications = {NULL, on_linked_write};
    UA_BrowseDescription bd;
    UA_BrowseResult result;
    UA_Variant parent;

    UA_Variant_init(&parent);
    if(UA_Server_readValue(server, *parent_id, &parent) != UA_STATUSCODE_GOOD)
        return;

    UA_BrowseDescription_init(&bd);
    bd.nodeId = *parent_id;
    bd.browseDirection = UA_BROWSEDIRECTION_FORWARD;
    bd.referenceTypeId = UA_NODEID_NUMERIC(0, UA_NS0ID_HASCOMPONENT);
    bd.includeSubtypes = true;
    bd.nodeClassMask = UA_NODECLASS_VARIABLE;
    bd.resultMask = UA_BROWSERESULTMASK_BROWSENAME;

    result = UA_Server_browse(server, 0, &bd);
    for(size_t i = 0; i < result.referencesSize; i++) {
        ValueLink link;
        ValueLink *grown = NULL;

        memset(&link, 0, sizeof(link));
        if(!resolve_slot(&parent, &result.references[i].browseName.name, &link))
            continue;

        grown = (ValueLink *)realloc(value_links,
                                     (value_links_size + 1) * sizeof(ValueLink));
        if(!grown)
            break;
        value_links = grown;
        UA_NodeId_copy(parent_id, &link.parent);
        UA_NodeId_copy(&result.references[i].nodeId.nodeId, &link.child);
        value_links[value_links_size++] = link;

        UA_Server_setVariableNode_internalValueSource(server, link.parent, NULL,
                                                      &notifications);
        UA_Server_setVariableNode_internalValueSource(server, link.child, NULL,
                                                      &notifications);
    }

    UA_BrowseResult_clear(&result);
    UA_Variant_clear(&parent);
}

/* Makes every parent value agree with its component Variables once after
 * linking, starting from the Variables that have no components of their own.
 * A zero-initialized structure holds null arrays where its component
 * Variables hold arrays of the declared size. */
static void
sync_value_links(UA_Server *server) {
    propagating = true;
    for(size_t i = 0; i < value_links_size; i++) {
        UA_Boolean leaf = true;
        for(size_t j = 0; leaf && j < value_links_size; j++)
            leaf = !UA_NodeId_equal(&value_links[j].parent, &value_links[i].child);
        if(leaf)
            propagate_up(server, &value_links[i].child);
    }
    propagating = false;
}

/* Releases the recorded value links. */
static void
clear_value_links(void) {
    for(size_t i = 0; i < value_links_size; i++) {
        UA_NodeId_clear(&value_links[i].parent);
        UA_NodeId_clear(&value_links[i].child);
    }
    free(value_links);
    value_links = NULL;
    value_links_size = 0;
}

/* Start value of one Variable: the value it holds once the models are loaded
 * and prepared. A CPU sets its tags back to their start values when it goes
 * from STOP to RUN. */
typedef struct {
    UA_NodeId node;
    UA_Variant value;
} StartValue;

static StartValue *start_values = NULL;
static size_t start_values_size = 0;

/* Records the current value of one Variable as its start value. */
static void
record_start_value(UA_Server *server, const UA_NodeId *id) {
    StartValue start;
    StartValue *grown = NULL;

    UA_Variant_init(&start.value);
    if(UA_Server_readValue(server, *id, &start.value) != UA_STATUSCODE_GOOD ||
       !start.value.type)
        return;

    grown = (StartValue *)realloc(start_values,
                                  (start_values_size + 1) * sizeof(StartValue));
    if(!grown || UA_NodeId_copy(id, &start.node) != UA_STATUSCODE_GOOD) {
        if(grown)
            start_values = grown;
        UA_Variant_clear(&start.value);
        return;
    }
    start_values = grown;
    start_values[start_values_size++] = start;
}

/* Writes every recorded start value back. The values are consistent among
 * linked Variables already, so the writes do not propagate. */
static void
restore_start_values(UA_Server *server) {
    propagating = true;
    for(size_t i = 0; i < start_values_size; i++)
        UA_Server_writeValue(server, start_values[i].node, start_values[i].value);
    propagating = false;
}

/* Releases the recorded start values. */
static void
clear_start_values(void) {
    for(size_t i = 0; i < start_values_size; i++) {
        UA_NodeId_clear(&start_values[i].node);
        UA_Variant_clear(&start_values[i].value);
    }
    free(start_values);
    start_values = NULL;
    start_values_size = 0;
}

/* Prepares every Variable of the loaded models, reachable from the Root
 * folder: initializes its value, links it to its component Variables, and
 * records its start value. */
static void
prepare_variables(UA_Server *server) {
    UA_BrowseDescription bd;
    UA_ExpandedNodeId *nodes = NULL;
    size_t nodes_size = 0;

    UA_BrowseDescription_init(&bd);
    bd.nodeId = UA_NODEID_NUMERIC(0, UA_NS0ID_ROOTFOLDER);
    bd.browseDirection = UA_BROWSEDIRECTION_FORWARD;
    bd.referenceTypeId = UA_NODEID_NUMERIC(0, UA_NS0ID_HIERARCHICALREFERENCES);
    bd.includeSubtypes = true;

    if(UA_Server_browseRecursive(server, &bd, &nodes_size, &nodes) !=
       UA_STATUSCODE_GOOD)
        return;

    for(int pass = 0; pass < 2; pass++) {
        for(size_t i = 0; i < nodes_size; i++) {
            UA_NodeClass node_class = UA_NODECLASS_UNSPECIFIED;
            if(nodes[i].nodeId.namespaceIndex == 0)
                continue;
            if(UA_Server_readNodeClass(server, nodes[i].nodeId, &node_class) !=
               UA_STATUSCODE_GOOD || node_class != UA_NODECLASS_VARIABLE)
                continue;
            if(pass == 0)
                init_value(server, &nodes[i].nodeId);
            else
                link_children(server, &nodes[i].nodeId);
        }
    }

    sync_value_links(server);
    for(size_t i = 0; i < nodes_size; i++) {
        UA_NodeClass node_class = UA_NODECLASS_UNSPECIFIED;
        if(nodes[i].nodeId.namespaceIndex != 0 &&
           UA_Server_readNodeClass(server, nodes[i].nodeId, &node_class) ==
           UA_STATUSCODE_GOOD && node_class == UA_NODECLASS_VARIABLE)
            record_start_value(server, &nodes[i].nodeId);
    }

    UA_LOG_INFO(UA_Log_Stdout, UA_LOGCATEGORY_APPLICATION,
                "linked %lu component values", (unsigned long)value_links_size);
    UA_Array_delete(nodes, nodes_size, &UA_TYPES[UA_TYPES_EXPANDEDNODEID]);
}

/* Operating state of the simulated CPU. In STOP the signals hold their last
 * value, clients can still read and write, and methods are rejected. */
static UA_Boolean cpu_running = true;

/* One simulated Variable. A random signal draws a new value in [min, max]
 * every period; a ramp adds step every period and restarts at min after max;
 * a toggle alternates between min and max every period; a sine swings between
 * min and max once per period and is evaluated at every simulation step. */
typedef enum { SIM_RANDOM, SIM_RAMP, SIM_TOGGLE, SIM_SINE } SimKind;

typedef struct {
    UA_NodeId node;
    SimKind kind;
    double min;
    double max;
    double step;
    double period_ms;
    double value;
    double elapsed_ms;
} SimSignal;

static SimSignal *sim_signals = NULL;
static size_t sim_signals_size = 0;
static double sim_cycle_ms = SIM_DEFAULT_CYCLE_MS;

/* Stores a number in one element of a numeric or Boolean data type, limited
 * to the range of that type. Returns false for any other data type. */
static UA_Boolean
set_number(void *element, const UA_DataType *type, double number) {
#define SIM_STORE(ctype, low, high)                                   \
    *(ctype *)element = (ctype)(number < (low) ? (low) :              \
                                number > (high) ? (high) : number);   \
    return true

    switch(type->typeKind) {
    case UA_DATATYPEKIND_BOOLEAN:
        *(UA_Boolean *)element = number >= 0.5;
        return true;
    case UA_DATATYPEKIND_SBYTE:  SIM_STORE(UA_SByte, -128.0, 127.0);
    case UA_DATATYPEKIND_BYTE:   SIM_STORE(UA_Byte, 0.0, 255.0);
    case UA_DATATYPEKIND_INT16:  SIM_STORE(UA_Int16, -32768.0, 32767.0);
    case UA_DATATYPEKIND_UINT16: SIM_STORE(UA_UInt16, 0.0, 65535.0);
    case UA_DATATYPEKIND_INT32:  SIM_STORE(UA_Int32, -2147483648.0, 2147483647.0);
    case UA_DATATYPEKIND_UINT32: SIM_STORE(UA_UInt32, 0.0, 4294967295.0);
    case UA_DATATYPEKIND_INT64:  SIM_STORE(UA_Int64, -9.2233720368547e18, 9.2233720368547e18);
    case UA_DATATYPEKIND_UINT64: SIM_STORE(UA_UInt64, 0.0, 1.8446744073709e19);
    case UA_DATATYPEKIND_FLOAT:
        *(UA_Float *)element = (UA_Float)number;
        return true;
    case UA_DATATYPEKIND_DOUBLE:
        *(UA_Double *)element = number;
        return true;
    default:
        return false;
    }
#undef SIM_STORE
}

/* Reads one element of a numeric or Boolean data type as a number. Returns
 * false for any other data type. */
static UA_Boolean
get_number(const void *element, const UA_DataType *type, double *number) {
    switch(type->typeKind) {
    case UA_DATATYPEKIND_BOOLEAN: *number = *(const UA_Boolean *)element ? 1.0 : 0.0; break;
    case UA_DATATYPEKIND_SBYTE:   *number = (double)*(const UA_SByte *)element; break;
    case UA_DATATYPEKIND_BYTE:    *number = (double)*(const UA_Byte *)element; break;
    case UA_DATATYPEKIND_INT16:   *number = (double)*(const UA_Int16 *)element; break;
    case UA_DATATYPEKIND_UINT16:  *number = (double)*(const UA_UInt16 *)element; break;
    case UA_DATATYPEKIND_INT32:   *number = (double)*(const UA_Int32 *)element; break;
    case UA_DATATYPEKIND_UINT32:  *number = (double)*(const UA_UInt32 *)element; break;
    case UA_DATATYPEKIND_INT64:   *number = (double)*(const UA_Int64 *)element; break;
    case UA_DATATYPEKIND_UINT64:  *number = (double)*(const UA_UInt64 *)element; break;
    case UA_DATATYPEKIND_FLOAT:   *number = (double)*(const UA_Float *)element; break;
    case UA_DATATYPEKIND_DOUBLE:  *number = *(const UA_Double *)element; break;
    default: return false;
    }
    return true;
}

/* Draws a uniformly distributed number in [min, max]. */
static double
random_between(double min, double max) {
    return min + (max - min) * ((double)rand() / (double)RAND_MAX);
}

/* Advances one signal by one simulation step. Returns true when the signal
 * has a new value to write. */
static UA_Boolean
advance_signal(SimSignal *signal) {
    signal->elapsed_ms += sim_cycle_ms;

    if(signal->kind == SIM_SINE) {
        double middle = (signal->max + signal->min) / 2.0;
        double amplitude = (signal->max - signal->min) / 2.0;
        signal->value = middle + amplitude *
            sin(SIM_TWO_PI * signal->elapsed_ms / signal->period_ms);
        return true;
    }

    if(signal->elapsed_ms < signal->period_ms)
        return false;
    signal->elapsed_ms = 0.0;

    switch(signal->kind) {
    case SIM_RAMP:
        signal->value += signal->step;
        if(signal->value > signal->max)
            signal->value = signal->min;
        break;
    case SIM_TOGGLE:
        signal->value = (signal->value == signal->min) ? signal->max : signal->min;
        break;
    default:
        signal->value = random_between(signal->min, signal->max);
        break;
    }
    return true;
}

/* Writes the current signal value into its Variable, keeping the data type
 * and array size the Variable holds. Every element of an array receives the
 * value; a random signal draws each element separately. Returns false when
 * the Variable cannot take a number. */
static UA_Boolean
write_signal(UA_Server *server, const SimSignal *signal) {
    UA_Variant value;
    size_t count = 0;
    UA_Boolean stored = true;

    UA_Variant_init(&value);
    if(UA_Server_readValue(server, signal->node, &value) != UA_STATUSCODE_GOOD)
        return false;
    if(!value.type || !value.data) {
        UA_Variant_clear(&value);
        return false;
    }

    count = UA_Variant_isScalar(&value) ? 1 : value.arrayLength;
    for(size_t i = 0; stored && i < count; i++) {
        void *element = (void *)((uintptr_t)value.data + i * value.type->memSize);
        double number = (signal->kind == SIM_RANDOM && i > 0)
                            ? random_between(signal->min, signal->max)
                            : signal->value;
        stored = set_number(element, value.type, number);
    }
    if(stored)
        stored = UA_Server_writeValue(server, signal->node, value) == UA_STATUSCODE_GOOD;

    UA_Variant_clear(&value);
    return stored;
}

/* Reads the scalar value of a Variable as a number. */
static UA_Boolean
read_number(UA_Server *server, const UA_NodeId *id, double *number) {
    UA_Variant value;
    UA_Boolean good = false;

    UA_Variant_init(&value);
    if(UA_Server_readValue(server, *id, &value) != UA_STATUSCODE_GOOD)
        return false;
    if(value.type && value.data && UA_Variant_isScalar(&value))
        good = get_number(value.data, value.type, number);
    UA_Variant_clear(&value);
    return good;
}

/* Returns true when the node exists and has the given node class. */
static UA_Boolean
node_has_class(UA_Server *server, const UA_NodeId *id, UA_NodeClass expected) {
    UA_NodeClass node_class = UA_NODECLASS_UNSPECIFIED;

    return UA_Server_readNodeClass(server, *id, &node_class) == UA_STATUSCODE_GOOD &&
           node_class == expected;
}

/* Writes a number into the scalar value of a Variable, keeping the data type
 * the Variable holds. The write is skipped when the value does not change. */
static UA_Boolean
write_number(UA_Server *server, const UA_NodeId *id, double number) {
    UA_Variant value;
    UA_Boolean good = false;
    double current = 0.0;

    UA_Variant_init(&value);
    if(UA_Server_readValue(server, *id, &value) != UA_STATUSCODE_GOOD)
        return false;
    if(value.type && value.data && UA_Variant_isScalar(&value) &&
       get_number(value.data, value.type, &current)) {
        good = set_number(value.data, value.type, number);
        if(good && current != number)
            good = UA_Server_writeValue(server, *id, value) == UA_STATUSCODE_GOOD;
    }
    UA_Variant_clear(&value);
    return good;
}

/* Logic elements of the simulated program, evaluated at every simulation
 * step after the signals. A pack element collects up to SIM_PACK_BITS Boolean
 * Variables into the bits of one integer Variable, the first Variable in bit
 * 0; a count element writes the number of true Variables instead. An
 * on-delay element sets its output after its input has been true for
 * the delay and clears the output when the input is false. The delay is a
 * constant or the value of a Variable in milliseconds; an optional Variable
 * receives the elapsed time in milliseconds. */
#define SIM_PACK_BITS 32

typedef struct {
    UA_NodeId target;
    UA_NodeId bits[SIM_PACK_BITS];
    size_t bits_size;
    UA_Boolean count;
} SimPack;

typedef struct {
    UA_NodeId input;
    UA_NodeId output;
    UA_NodeId delay_node;
    UA_NodeId elapsed_node;
    UA_Boolean has_delay_node;
    UA_Boolean has_elapsed_node;
    double delay_ms;
    double elapsed_ms;
} SimOnDelay;

static SimPack *sim_packs = NULL;
static size_t sim_packs_size = 0;
static SimOnDelay *sim_on_delays = NULL;
static size_t sim_on_delays_size = 0;

/* Evaluates all logic elements once. */
static void
logic_step(UA_Server *server) {
    for(size_t i = 0; i < sim_on_delays_size; i++) {
        SimOnDelay *element = &sim_on_delays[i];
        double input = 0.0;
        if(!read_number(server, &element->input, &input))
            continue;
        if(element->has_delay_node)
            read_number(server, &element->delay_node, &element->delay_ms);
        if(input < 0.5)
            element->elapsed_ms = 0.0;
        else if(element->elapsed_ms < element->delay_ms)
            element->elapsed_ms += sim_cycle_ms;
        if(element->elapsed_ms > element->delay_ms)
            element->elapsed_ms = element->delay_ms;
        if(element->has_elapsed_node)
            write_number(server, &element->elapsed_node, element->elapsed_ms);
        write_number(server, &element->output,
                     (input >= 0.5 && element->elapsed_ms >= element->delay_ms) ? 1.0 : 0.0);
    }

    for(size_t i = 0; i < sim_packs_size; i++) {
        double packed = 0.0;
        for(size_t bit = 0; bit < sim_packs[i].bits_size; bit++) {
            double set = 0.0;
            if(read_number(server, &sim_packs[i].bits[bit], &set) && set >= 0.5)
                packed += sim_packs[i].count ? 1.0 : (double)((UA_UInt64)1 << bit);
        }
        write_number(server, &sim_packs[i].target, packed);
    }
}

/* Reads one line "pack <target-node-id> <bit-node-id> ..." or the same line
 * with the keyword "count". */
static UA_Boolean
parse_pack(UA_Server *server, char *arguments, UA_Boolean count) {
    SimPack pack;
    SimPack *grown = NULL;
    char *save = NULL;
    char *token = strtok_r(arguments, " \t", &save);
    UA_Boolean good = token != NULL;
    double number = 0.0;

    memset(&pack, 0, sizeof(pack));
    pack.count = count;
    good = good && UA_NodeId_parse(&pack.target, UA_STRING(token)) == UA_STATUSCODE_GOOD &&
           read_number(server, &pack.target, &number);
    for(token = strtok_r(NULL, " \t", &save); good && token;
        token = strtok_r(NULL, " \t", &save)) {
        good = pack.bits_size < SIM_PACK_BITS &&
               UA_NodeId_parse(&pack.bits[pack.bits_size], UA_STRING(token)) ==
                   UA_STATUSCODE_GOOD;
        if(good)
            good = read_number(server, &pack.bits[pack.bits_size++], &number);
    }
    good = good && pack.bits_size > 0;
    if(good)
        grown = (SimPack *)realloc(sim_packs, (sim_packs_size + 1) * sizeof(SimPack));
    if(!grown) {
        UA_NodeId_clear(&pack.target);
        for(size_t bit = 0; bit < pack.bits_size; bit++)
            UA_NodeId_clear(&pack.bits[bit]);
        return false;
    }
    sim_packs = grown;
    sim_packs[sim_packs_size++] = pack;
    return true;
}

/* Reads one line
 * "on-delay <input-node-id> <output-node-id> delay=<ms|node-id> [elapsed=<node-id>]". */
static UA_Boolean
parse_on_delay(UA_Server *server, char *arguments) {
    SimOnDelay element;
    SimOnDelay *grown = NULL;
    char *save = NULL;
    char *input = strtok_r(arguments, " \t", &save);
    char *output = strtok_r(NULL, " \t", &save);
    char *delay = strtok_r(NULL, " \t", &save);
    char *elapsed = strtok_r(NULL, " \t", &save);
    char *end = NULL;
    double number = 0.0;
    UA_Boolean good = false;

    memset(&element, 0, sizeof(element));
    if(!input || !output || !delay || strncmp(delay, "delay=", 6) != 0 ||
       (elapsed && strncmp(elapsed, "elapsed=", 8) != 0) || strtok_r(NULL, " \t", &save))
        return false;

    element.delay_ms = strtod(delay + 6, &end);
    if(end == delay + 6 || *end != '\0') {
        element.has_delay_node =
            UA_NodeId_parse(&element.delay_node, UA_STRING(delay + 6)) == UA_STATUSCODE_GOOD &&
            read_number(server, &element.delay_node, &element.delay_ms);
        good = element.has_delay_node;
    } else {
        good = element.delay_ms >= 0.0;
    }
    if(good && elapsed) {
        element.has_elapsed_node =
            UA_NodeId_parse(&element.elapsed_node, UA_STRING(elapsed + 8)) == UA_STATUSCODE_GOOD &&
            read_number(server, &element.elapsed_node, &number);
        good = element.has_elapsed_node;
    }

    if(good &&
       UA_NodeId_parse(&element.input, UA_STRING(input)) == UA_STATUSCODE_GOOD &&
       UA_NodeId_parse(&element.output, UA_STRING(output)) == UA_STATUSCODE_GOOD &&
       read_number(server, &element.input, &number) &&
       read_number(server, &element.output, &number))
        grown = (SimOnDelay *)realloc(sim_on_delays,
                                      (sim_on_delays_size + 1) * sizeof(SimOnDelay));
    if(!grown) {
        UA_NodeId_clear(&element.input);
        UA_NodeId_clear(&element.output);
        UA_NodeId_clear(&element.delay_node);
        UA_NodeId_clear(&element.elapsed_node);
        return false;
    }
    sim_on_delays = grown;
    sim_on_delays[sim_on_delays_size++] = element;
    return true;
}

/* One simulated alarm. An alarm with a state is a Condition: it becomes
 * active when its trigger Variable becomes true and inactive when the trigger
 * becomes false, and reports each change as an event. An alarm without a
 * state reports one event each time its trigger becomes true. */
typedef struct {
    UA_NodeId trigger;
    UA_NodeId source;
    UA_NodeId type;
    UA_NodeId condition;
    UA_Boolean stateful;
    UA_Boolean active;
    UA_UInt16 severity;
    char *message;
    UA_KeyValuePair *fields;
    size_t fields_size;
    int queue;
    UA_Boolean outstanding;
    unsigned long order;
} SimAlarm;

static SimAlarm *sim_alarms = NULL;
static size_t sim_alarms_size = 0;

/* Sets the active state of a Condition and reports the change as one event
 * that carries the alarm message. The server reports the change to active on
 * its own when the state is written; the change to inactive is reported
 * explicitly. */
static void
report_condition(UA_Server *server, const SimAlarm *alarm) {
    UA_DateTime now = UA_DateTime_now();
    UA_LocalizedText message = UA_LOCALIZEDTEXT(SIM_LOCALE, alarm->message);
    UA_Boolean active = alarm->active;
    UA_Variant value;
    UA_StatusCode status = UA_STATUSCODE_GOOD;

    status |= UA_Server_writeObjectProperty_scalar(server, alarm->condition,
                                                   UA_QUALIFIEDNAME(0, "Time"), &now,
                                                   &UA_TYPES[UA_TYPES_DATETIME]);
    status |= UA_Server_writeObjectProperty_scalar(server, alarm->condition,
                                                   UA_QUALIFIEDNAME(0, "Message"), &message,
                                                   &UA_TYPES[UA_TYPES_LOCALIZEDTEXT]);
    status |= UA_Server_writeObjectProperty_scalar(server, alarm->condition,
                                                   UA_QUALIFIEDNAME(0, "Retain"), &active,
                                                   &UA_TYPES[UA_TYPES_BOOLEAN]);
    if(active) {
        UA_Boolean acked = false;
        UA_Variant_setScalar(&value, &acked, &UA_TYPES[UA_TYPES_BOOLEAN]);
        status |= UA_Server_setConditionVariableFieldProperty(
            server, alarm->condition, &value, UA_QUALIFIEDNAME(0, "AckedState"),
            UA_QUALIFIEDNAME(0, "Id"));
    }
    UA_Variant_setScalar(&value, &active, &UA_TYPES[UA_TYPES_BOOLEAN]);
    status |= UA_Server_setConditionVariableFieldProperty(server, alarm->condition, &value,
                                                          UA_QUALIFIEDNAME(0, "ActiveState"),
                                                          UA_QUALIFIEDNAME(0, "Id"));
    if(!active)
        status |= UA_Server_triggerConditionEvent(server, alarm->condition, alarm->source,
                                                  NULL);
    if(status != UA_STATUSCODE_GOOD)
        UA_LOG_WARNING(UA_Log_Stdout, UA_LOGCATEGORY_APPLICATION,
                       "cannot report the alarm \"%s\": %s", alarm->message,
                       UA_StatusCode_name(status));
}

/* An alarm queue of the CPU. The alarms with a state whose source Object is
 * the source of the queue belong to it. At most "max" of them are active; the
 * others are outstanding and become active, oldest first, when room frees. The
 * overload trigger is true from the moment the active alarms reach the maximum
 * until no alarm is outstanding and their number is below the maximum minus
 * the hysteresis. */
typedef struct {
    UA_NodeId max_node;
    UA_NodeId hysteresis_node;
    UA_NodeId current_node;
    UA_NodeId outstanding_node;
    UA_NodeId source;
    UA_NodeId overload_trigger;
    UA_Boolean overload;
} SimQueue;

static SimQueue *sim_queues = NULL;
static size_t sim_queues_size = 0;
static unsigned long sim_alarm_order = 0;

/* Starts or ends the alarm of one member of a queue and records its place. */
static void
queue_member_step(UA_Server *server, SimAlarm *alarm, UA_Boolean wanted, double max,
                  double active_count) {
    if(wanted && !alarm->active && !alarm->outstanding) {
        if(active_count < max) {
            alarm->active = true;
            report_condition(server, alarm);
        } else {
            alarm->outstanding = true;
            alarm->order = ++sim_alarm_order;
        }
    } else if(!wanted && alarm->outstanding) {
        alarm->outstanding = false;
    } else if(!wanted && alarm->active) {
        alarm->active = false;
        report_condition(server, alarm);
    }
}

/* Follows the triggers of the members of one queue, activates outstanding
 * alarms while there is room, and publishes the counts and the overload. */
static void
queue_step(UA_Server *server, size_t index) {
    SimQueue *queue = &sim_queues[index];
    double max = 0.0;
    double hysteresis = 0.0;
    double active_count = 0.0;
    double outstanding_count = 0.0;

    if(!read_number(server, &queue->max_node, &max) ||
       !read_number(server, &queue->hysteresis_node, &hysteresis))
        return;
    for(size_t i = 0; i < sim_alarms_size; i++) {
        double trigger = 0.0;
        if(sim_alarms[i].queue != (int)index || !read_number(server, &sim_alarms[i].trigger, &trigger))
            continue;
        active_count = 0.0;
        for(size_t k = 0; k < sim_alarms_size; k++)
            active_count += (sim_alarms[k].queue == (int)index && sim_alarms[k].active) ? 1.0 : 0.0;
        queue_member_step(server, &sim_alarms[i], trigger >= 0.5, max, active_count);
    }

    /* Outstanding alarms become active, oldest first, while there is room. */
    for(;;) {
        SimAlarm *oldest = NULL;
        active_count = 0.0;
        for(size_t k = 0; k < sim_alarms_size; k++) {
            SimAlarm *alarm = &sim_alarms[k];
            if(alarm->queue != (int)index)
                continue;
            active_count += alarm->active ? 1.0 : 0.0;
            if(alarm->outstanding && (!oldest || alarm->order < oldest->order))
                oldest = alarm;
        }
        if(!oldest || active_count >= max)
            break;
        oldest->outstanding = false;
        oldest->active = true;
        report_condition(server, oldest);
    }

    active_count = 0.0;
    for(size_t k = 0; k < sim_alarms_size; k++) {
        if(sim_alarms[k].queue != (int)index)
            continue;
        active_count += sim_alarms[k].active ? 1.0 : 0.0;
        outstanding_count += sim_alarms[k].outstanding ? 1.0 : 0.0;
    }
    if(!queue->overload && active_count >= max)
        queue->overload = true;
    else if(queue->overload && outstanding_count == 0.0 && active_count < max - hysteresis)
        queue->overload = false;
    write_number(server, &queue->current_node, active_count);
    write_number(server, &queue->outstanding_node, outstanding_count);
    write_number(server, &queue->overload_trigger, queue->overload ? 1.0 : 0.0);
}

/* Follows the trigger of every alarm once. */
static void
alarm_step(UA_Server *server) {
    for(size_t q = 0; q < sim_queues_size; q++)
        queue_step(server, q);
    for(size_t i = 0; i < sim_alarms_size; i++) {
        SimAlarm *alarm = &sim_alarms[i];
        double trigger = 0.0;
        UA_Boolean active = false;

        if(alarm->queue >= 0 || !read_number(server, &alarm->trigger, &trigger))
            continue;
        active = trigger >= 0.5;
        if(active == alarm->active)
            continue;
        alarm->active = active;

        if(alarm->stateful) {
            report_condition(server, alarm);
        } else if(active) {
            UA_KeyValueMap fields = {alarm->fields_size, alarm->fields};
            UA_StatusCode status =
                UA_Server_createEvent(server, alarm->source, alarm->type, alarm->severity,
                                      UA_LOCALIZEDTEXT(SIM_LOCALE, alarm->message),
                                      alarm->fields_size ? &fields : NULL, NULL, NULL);
            if(status != UA_STATUSCODE_GOOD)
                UA_LOG_WARNING(UA_Log_Stdout, UA_LOGCATEGORY_APPLICATION,
                               "cannot report the event \"%s\": %s", alarm->message,
                               UA_StatusCode_name(status));
        }
    }
}

/* Reads one line
 * "alarm <type-node-id> <source-node-id> <trigger-node-id> <severity> <message>"
 * or the same line with the keyword "event". The type is a subtype of
 * ConditionType for an alarm and of BaseEventType for an event; the source is
 * the Object that reports it; the message runs to the end of the line. */
static UA_Boolean
parse_alarm(UA_Server *server, char *arguments, UA_Boolean stateful) {
    SimAlarm alarm;
    SimAlarm *grown = NULL;
    char *save = NULL;
    char *type = strtok_r(arguments, " \t", &save);
    char *source = strtok_r(NULL, " \t", &save);
    char *trigger = strtok_r(NULL, " \t", &save);
    char *severity = strtok_r(NULL, " \t", &save);
    char *end = NULL;
    long level = severity ? strtol(severity, &end, 10) : 0;
    double number = 0.0;
    UA_Boolean good = false;

    memset(&alarm, 0, sizeof(alarm));
    if(!type || !source || !trigger || !severity || end == severity || *end != '\0' ||
       level < 1 || level > 1000 || !save)
        return false;
    save += strspn(save, " \t");
    if(*save == '\0')
        return false;
    alarm.stateful = stateful;
    alarm.queue = -1;
    alarm.severity = (UA_UInt16)level;

    good = UA_NodeId_parse(&alarm.type, UA_STRING(type)) == UA_STATUSCODE_GOOD &&
           UA_NodeId_parse(&alarm.source, UA_STRING(source)) == UA_STATUSCODE_GOOD &&
           UA_NodeId_parse(&alarm.trigger, UA_STRING(trigger)) == UA_STATUSCODE_GOOD &&
           node_has_class(server, &alarm.type, UA_NODECLASS_OBJECTTYPE) &&
           node_has_class(server, &alarm.source, UA_NODECLASS_OBJECT) &&
           read_number(server, &alarm.trigger, &number);
    if(good && stateful) {
        UA_Boolean enabled = true;
        UA_LocalizedText message = UA_LOCALIZEDTEXT(SIM_LOCALE, save);
        UA_Variant value;
        UA_Variant_setScalar(&value, &enabled, &UA_TYPES[UA_TYPES_BOOLEAN]);
        good = UA_Server_createCondition(server, UA_NODEID_NULL, alarm.type,
                                         UA_QUALIFIEDNAME(0, save), alarm.source,
                                         UA_NODEID_NULL, &alarm.condition) ==
                   UA_STATUSCODE_GOOD &&
               UA_Server_setConditionVariableFieldProperty(
                   server, alarm.condition, &value, UA_QUALIFIEDNAME(0, "EnabledState"),
                   UA_QUALIFIEDNAME(0, "Id")) == UA_STATUSCODE_GOOD &&
               UA_Server_writeObjectProperty_scalar(
                   server, alarm.condition, UA_QUALIFIEDNAME(0, "Severity"),
                   &alarm.severity, &UA_TYPES[UA_TYPES_UINT16]) == UA_STATUSCODE_GOOD &&
               UA_Server_writeObjectProperty_scalar(
                   server, alarm.condition, UA_QUALIFIEDNAME(0, "Message"), &message,
                   &UA_TYPES[UA_TYPES_LOCALIZEDTEXT]) == UA_STATUSCODE_GOOD;
    }
    if(good)
        alarm.message = strdup(save);
    if(alarm.message)
        grown = (SimAlarm *)realloc(sim_alarms, (sim_alarms_size + 1) * sizeof(SimAlarm));
    if(!grown) {
        UA_NodeId_clear(&alarm.type);
        UA_NodeId_clear(&alarm.source);
        UA_NodeId_clear(&alarm.trigger);
        UA_NodeId_clear(&alarm.condition);
        free(alarm.message);
        return false;
    }
    sim_alarms = grown;
    sim_alarms[sim_alarms_size++] = alarm;
    return true;
}

/* Reads one line "queue <max-node> <hysteresis-node> <current-node>
 * <outstanding-node> <source-node> <overload-trigger-node>". */
static UA_Boolean
parse_queue(UA_Server *server, char *arguments) {
    SimQueue queue;
    SimQueue *grown = NULL;
    char *save = NULL;
    char *token[6];
    double number = 0.0;
    UA_Boolean good = true;

    memset(&queue, 0, sizeof(queue));
    token[0] = strtok_r(arguments, " \t", &save);
    for(size_t i = 1; i < 6; i++)
        token[i] = strtok_r(NULL, " \t", &save);
    for(size_t i = 0; i < 6; i++)
        good = good && token[i];
    if(!good || strtok_r(NULL, " \t", &save))
        return false;

    good = UA_NodeId_parse(&queue.max_node, UA_STRING(token[0])) == UA_STATUSCODE_GOOD &&
           UA_NodeId_parse(&queue.hysteresis_node, UA_STRING(token[1])) == UA_STATUSCODE_GOOD &&
           UA_NodeId_parse(&queue.current_node, UA_STRING(token[2])) == UA_STATUSCODE_GOOD &&
           UA_NodeId_parse(&queue.outstanding_node, UA_STRING(token[3])) == UA_STATUSCODE_GOOD &&
           UA_NodeId_parse(&queue.source, UA_STRING(token[4])) == UA_STATUSCODE_GOOD &&
           UA_NodeId_parse(&queue.overload_trigger, UA_STRING(token[5])) == UA_STATUSCODE_GOOD &&
           read_number(server, &queue.max_node, &number) &&
           read_number(server, &queue.hysteresis_node, &number) &&
           read_number(server, &queue.current_node, &number) &&
           read_number(server, &queue.outstanding_node, &number) &&
           read_number(server, &queue.overload_trigger, &number) &&
           node_has_class(server, &queue.source, UA_NODECLASS_OBJECT);
    if(good)
        grown = (SimQueue *)realloc(sim_queues, (sim_queues_size + 1) * sizeof(SimQueue));
    if(!grown) {
        UA_NodeId_clear(&queue.max_node);
        UA_NodeId_clear(&queue.hysteresis_node);
        UA_NodeId_clear(&queue.current_node);
        UA_NodeId_clear(&queue.outstanding_node);
        UA_NodeId_clear(&queue.source);
        UA_NodeId_clear(&queue.overload_trigger);
        return false;
    }
    sim_queues = grown;
    sim_queues[sim_queues_size++] = queue;
    return true;
}

/* Assigns each alarm with a state to the first queue of its source Object. */
static void
bind_queues(void) {
    for(size_t i = 0; i < sim_alarms_size; i++) {
        sim_alarms[i].queue = -1;
        for(size_t q = 0; sim_alarms[i].stateful && q < sim_queues_size; q++) {
            if(sim_alarms[i].queue < 0 && UA_NodeId_equal(&sim_alarms[i].source, &sim_queues[q].source))
                sim_alarms[i].queue = (int)q;
        }
    }
}

/* Namespace URI of the SIMATIC interface; the event fields belong to it. */
#define SIM_SIMATIC_URI "http://www.siemens.com/simatic-s7-opcua"

typedef enum { FIELD_TEXT, FIELD_UINT16, FIELD_BYTE, FIELD_UNKNOWN } FieldKind;

/* Data type of an event field that a "field" line can set. */
static FieldKind
field_kind(const char *name) {
    if(strcmp(name, "InfoText") == 0)
        return FIELD_TEXT;
    if(strncmp(name, "AdditionalText_0", 16) == 0 && name[16] >= '1' && name[16] <= '9' &&
       name[17] == '\0')
        return FIELD_TEXT;
    if(strcmp(name, "ID") == 0 || strcmp(name, "DisplayClass") == 0)
        return FIELD_UINT16;
    if(strcmp(name, "GroupID") == 0)
        return FIELD_BYTE;
    return FIELD_UNKNOWN;
}

/* Reads one line "field <trigger-node-id> <browse-name> <value>": sets an
 * event field of the alarm or event that the trigger names. The value is the
 * rest of the line. The line follows the alarm or event line of the trigger. */
static UA_Boolean
parse_field(UA_Server *server, char *arguments) {
    char *save = NULL;
    char *trigger_text = strtok_r(arguments, " \t", &save);
    char *name = strtok_r(NULL, " \t", &save);
    char *value_text = NULL;
    char *end = NULL;
    char key_name[128];
    UA_NodeId trigger = UA_NODEID_NULL;
    size_t ns = 0;
    SimAlarm *alarm = NULL;
    UA_KeyValuePair field;
    UA_KeyValuePair *grown = NULL;
    FieldKind kind = FIELD_UNKNOWN;
    long number = 0;
    UA_Boolean good = false;

    if(!trigger_text || !name || !save)
        return false;
    value_text = save + strspn(save, " \t");
    kind = field_kind(name);
    if(*value_text == '\0' || kind == FIELD_UNKNOWN ||
       UA_NodeId_parse(&trigger, UA_STRING(trigger_text)) != UA_STATUSCODE_GOOD)
        return false;
    for(size_t i = 0; i < sim_alarms_size; i++) {
        if(UA_NodeId_equal(&sim_alarms[i].trigger, &trigger))
            alarm = &sim_alarms[i];
    }
    UA_NodeId_clear(&trigger);
    if(!alarm || UA_Server_getNamespaceByName(server, UA_STRING(SIM_SIMATIC_URI), &ns) !=
                     UA_STATUSCODE_GOOD)
        return false;
    /* An event reads its fields from a map whose keys are paths of the form
     * "/<name>", read in the namespace of the key; a Condition holds them as
     * properties with the plain browse name. */
    if(snprintf(key_name, sizeof(key_name), "%s%s", alarm->stateful ? "" : "/", name) >=
       (int)sizeof(key_name))
        return false;
    for(size_t i = 0; i < alarm->fields_size; i++) {
        if(strlen(key_name) == alarm->fields[i].key.name.length &&
           memcmp(key_name, alarm->fields[i].key.name.data, strlen(key_name)) == 0)
            return false;
    }

    memset(&field, 0, sizeof(field));
    field.key = UA_QUALIFIEDNAME_ALLOC((UA_UInt16)ns, key_name);
    if(kind == FIELD_TEXT) {
        UA_LocalizedText text = UA_LOCALIZEDTEXT_ALLOC(SIM_LOCALE, value_text);
        good = UA_Variant_setScalarCopy(&field.value, &text,
                                        &UA_TYPES[UA_TYPES_LOCALIZEDTEXT]) ==
               UA_STATUSCODE_GOOD;
        UA_LocalizedText_clear(&text);
    } else {
        number = strtol(value_text, &end, 10);
        if(end != value_text && *end == '\0' && number >= 0 &&
           number <= (kind == FIELD_BYTE ? 255 : 65535)) {
            UA_UInt16 wide = (UA_UInt16)number;
            UA_Byte narrow = (UA_Byte)number;
            good = kind == FIELD_BYTE
                       ? UA_Variant_setScalarCopy(&field.value, &narrow,
                                                  &UA_TYPES[UA_TYPES_BYTE]) == UA_STATUSCODE_GOOD
                       : UA_Variant_setScalarCopy(&field.value, &wide,
                                                  &UA_TYPES[UA_TYPES_UINT16]) == UA_STATUSCODE_GOOD;
        }
    }
    if(good && alarm->stateful)
        good = UA_Server_writeObjectProperty(server, alarm->condition, field.key,
                                             field.value) == UA_STATUSCODE_GOOD;
    if(good) {
        grown = (UA_KeyValuePair *)realloc(alarm->fields,
                                           (alarm->fields_size + 1) * sizeof(UA_KeyValuePair));
        good = grown != NULL;
        if(grown) {
            alarm->fields = grown;
            alarm->fields[alarm->fields_size++] = field;
        }
    }
    if(!good) {
        UA_QualifiedName_clear(&field.key);
        UA_Variant_clear(&field.value);
    }
    return good;
}

/* Runs one simulation step: all signals, then all logic elements, then all
 * alarms. */
static void
simulation_step(UA_Server *server, void *data) {
    (void)data;
    if(!cpu_running)
        return;
    for(size_t i = 0; i < sim_signals_size; i++) {
        if(advance_signal(&sim_signals[i]))
            write_signal(server, &sim_signals[i]);
    }
    logic_step(server);
    alarm_step(server);
}

/* Reads one "key=value" parameter of a signal line into the signal. */
static UA_Boolean
parse_signal_parameter(SimSignal *signal, const char *token) {
    const char *equals = strchr(token, '=');
    char *end = NULL;
    double number = 0.0;
    size_t key_length = 0;

    if(!equals)
        return false;
    number = strtod(equals + 1, &end);
    if(end == equals + 1 || *end != '\0')
        return false;

    key_length = (size_t)(equals - token);
    if(key_length == 3 && strncmp(token, "min", key_length) == 0)
        signal->min = number;
    else if(key_length == 3 && strncmp(token, "max", key_length) == 0)
        signal->max = number;
    else if(key_length == 4 && strncmp(token, "step", key_length) == 0)
        signal->step = number;
    else if(key_length == 6 && strncmp(token, "period", key_length) == 0)
        signal->period_ms = number;
    else
        return false;
    return true;
}

/* Reads one signal line, "signal <node-id> <kind> [key=value ...]", checks
 * the Variable against the loaded models, and records the signal. */
static UA_Boolean
parse_signal(UA_Server *server, char *arguments) {
    static const char *kinds[] = {"random", "ramp", "toggle", "sine"};
    SimSignal signal;
    SimSignal *grown = NULL;
    char *save = NULL;
    char *node = strtok_r(arguments, " \t", &save);
    char *kind = strtok_r(NULL, " \t", &save);
    UA_Boolean known_kind = false;

    memset(&signal, 0, sizeof(signal));
    signal.min = SIM_DEFAULT_MIN;
    signal.max = SIM_DEFAULT_MAX;
    signal.step = SIM_DEFAULT_STEP;
    signal.period_ms = SIM_DEFAULT_PERIOD_MS;

    if(!node || !kind)
        return false;
    for(size_t i = 0; i < sizeof(kinds) / sizeof(kinds[0]); i++) {
        if(strcmp(kind, kinds[i]) == 0) {
            signal.kind = (SimKind)i;
            known_kind = true;
        }
    }
    if(!known_kind)
        return false;

    for(char *token = strtok_r(NULL, " \t", &save); token;
        token = strtok_r(NULL, " \t", &save)) {
        if(!parse_signal_parameter(&signal, token))
            return false;
    }
    if(signal.max < signal.min || signal.period_ms <= 0.0)
        return false;
    signal.value = signal.min;

    if(UA_NodeId_parse(&signal.node, UA_STRING(node)) != UA_STATUSCODE_GOOD)
        return false;
    if(!write_signal(server, &signal)) {
        UA_NodeId_clear(&signal.node);
        return false;
    }

    grown = (SimSignal *)realloc(sim_signals, (sim_signals_size + 1) * sizeof(SimSignal));
    if(!grown) {
        UA_NodeId_clear(&signal.node);
        return false;
    }
    sim_signals = grown;
    sim_signals[sim_signals_size++] = signal;
    return true;
}

/* One simulated server method. An echo method returns its input arguments
 * as output arguments, position by position. An accept method returns no
 * values. A sum method returns the sum of its numeric input arguments in the
 * data type of the first one. A sort method returns each input array sorted
 * in ascending order. A method with a busy time rejects calls that arrive
 * before the time since the last accepted call has passed, as a method
 * instance of a device accepts one call at a time. */
typedef enum { METHOD_ECHO, METHOD_ACCEPT, METHOD_SUM, METHOD_SORT } MethodKind;

typedef struct {
    UA_NodeId node;
    MethodKind kind;
    double busy_ms;
    UA_DateTime busy_until;
    UA_NodeId in_node;
    UA_NodeId out_node;
    UA_Boolean has_in;
    UA_Boolean has_out;
} SimMethod;

static SimMethod *sim_methods = NULL;
static size_t sim_methods_size = 0;

/* Sorts an array of a numeric data type in place, in ascending order. */
static void
sort_array(UA_Variant *array) {
    size_t size = array->type->memSize;
    UA_UInt64 held = 0;

    for(size_t end = array->arrayLength; end > 1; end--) {
        for(size_t i = 0; i + 1 < end; i++) {
            void *left = (void *)((uintptr_t)array->data + i * size);
            void *right = (void *)((uintptr_t)left + size);
            if(UA_order(left, right, array->type) != UA_ORDER_MORE)
                continue;
            memcpy(&held, left, size);
            memcpy(left, right, size);
            memcpy(right, &held, size);
        }
    }
}

/* Writes the values of the arguments of a call into the member Variables of
 * a structure Variable. The name of an argument, from the InputArguments or
 * OutputArguments property of the Method, selects the member with the same
 * browse name. A device holds the parameters of the last call in the static
 * data of the method instance in the same way. */
static void
store_arguments(UA_Server *server, const UA_NodeId *method_id, const char *property,
                const UA_NodeId *structure, size_t size, const UA_Variant *values) {
    UA_Variant arguments;
    UA_BrowseDescription bd;
    UA_BrowseResult result;

    UA_Variant_init(&arguments);
    if(UA_Server_readObjectProperty(server, *method_id,
                                    UA_QUALIFIEDNAME(0, (char *)(uintptr_t)property),
                                    &arguments) != UA_STATUSCODE_GOOD)
        return;
    if(!UA_Variant_hasArrayType(&arguments, &UA_TYPES[UA_TYPES_ARGUMENT])) {
        UA_Variant_clear(&arguments);
        return;
    }

    UA_BrowseDescription_init(&bd);
    bd.nodeId = *structure;
    bd.browseDirection = UA_BROWSEDIRECTION_FORWARD;
    bd.referenceTypeId = UA_NODEID_NUMERIC(0, UA_NS0ID_HASCOMPONENT);
    bd.includeSubtypes = true;
    bd.nodeClassMask = UA_NODECLASS_VARIABLE;
    bd.resultMask = UA_BROWSERESULTMASK_BROWSENAME;
    result = UA_Server_browse(server, 0, &bd);

    for(size_t i = 0; i < size && i < arguments.arrayLength; i++) {
        const UA_Argument *argument = &((const UA_Argument *)arguments.data)[i];
        for(size_t r = 0; r < result.referencesSize; r++) {
            if(!UA_String_equal(&result.references[r].browseName.name, &argument->name))
                continue;
            UA_Server_writeValue(server, result.references[r].nodeId.nodeId, values[i]);
            break;
        }
    }

    UA_BrowseResult_clear(&result);
    UA_Variant_clear(&arguments);
}

/* Returns BadInvalidArgument when an input argument that the method declares
 * as an array of fixed length arrives with another length, as a device
 * rejects a call with a wrong array length. */
static UA_StatusCode
check_input_lengths(UA_Server *server, const UA_NodeId *method_id, size_t size,
                    const UA_Variant *input) {
    UA_Variant arguments;
    UA_StatusCode status = UA_STATUSCODE_GOOD;

    UA_Variant_init(&arguments);
    if(UA_Server_readObjectProperty(server, *method_id,
                                    UA_QUALIFIEDNAME(0, "InputArguments"),
                                    &arguments) != UA_STATUSCODE_GOOD)
        return UA_STATUSCODE_GOOD;

    if(UA_Variant_hasArrayType(&arguments, &UA_TYPES[UA_TYPES_ARGUMENT])) {
        for(size_t i = 0; status == UA_STATUSCODE_GOOD && i < size &&
                          i < arguments.arrayLength; i++) {
            const UA_Argument *argument = &((const UA_Argument *)arguments.data)[i];
            if(argument->arrayDimensionsSize == 1 && argument->arrayDimensions[0] > 0 &&
               !UA_Variant_isScalar(&input[i]) &&
               input[i].arrayLength != argument->arrayDimensions[0])
                status = UA_STATUSCODE_BADINVALIDARGUMENT;
        }
    }

    UA_Variant_clear(&arguments);
    return status;
}

/* Serves a call of a simulated method. */
static UA_StatusCode
method_callback(UA_Server *server, const UA_NodeId *session_id,
                void *session_context, const UA_NodeId *method_id,
                void *method_context, const UA_NodeId *object_id,
                void *object_context, size_t input_size, const UA_Variant *input,
                size_t output_size, UA_Variant *output) {
    SimMethod *method = NULL;
    UA_DateTime now = UA_DateTime_nowMonotonic();
    UA_StatusCode length_status = UA_STATUSCODE_GOOD;

    (void)session_id;
    (void)session_context;
    (void)method_context;
    (void)object_id;
    (void)object_context;

    if(!cpu_running)
        return UA_STATUSCODE_BADINVALIDSTATE;

    for(size_t i = 0; !method && i < sim_methods_size; i++) {
        if(UA_NodeId_equal(&sim_methods[i].node, method_id))
            method = &sim_methods[i];
    }
    if(!method)
        return UA_STATUSCODE_BADMETHODINVALID;

    if(now < method->busy_until)
        return UA_STATUSCODE_BADINVALIDSTATE;
    length_status = check_input_lengths(server, method_id, input_size, input);
    if(length_status != UA_STATUSCODE_GOOD)
        return length_status;
    method->busy_until = now + (UA_DateTime)(method->busy_ms * UA_DATETIME_MSEC);

    if(method->kind == METHOD_ECHO || method->kind == METHOD_SORT) {
        for(size_t i = 0; i < input_size && i < output_size; i++) {
            UA_StatusCode status = UA_Variant_copy(&input[i], &output[i]);
            double number = 0.0;
            if(status != UA_STATUSCODE_GOOD)
                return status;
            if(method->kind == METHOD_SORT && output[i].type && output[i].arrayLength > 0 &&
               !UA_Variant_isScalar(&output[i]) &&
               get_number(output[i].data, output[i].type, &number))
                sort_array(&output[i]);
        }
    } else if(method->kind == METHOD_SUM && input_size > 0 && output_size > 0) {
        double sum = 0.0;
        UA_StatusCode status = UA_STATUSCODE_GOOD;
        for(size_t i = 0; i < input_size; i++) {
            double number = 0.0;
            if(!input[i].type || !UA_Variant_isScalar(&input[i]) ||
               !get_number(input[i].data, input[i].type, &number))
                return UA_STATUSCODE_BADTYPEMISMATCH;
            sum += number;
        }
        status = UA_Variant_copy(&input[0], &output[0]);
        if(status != UA_STATUSCODE_GOOD)
            return status;
        set_number(output[0].data, output[0].type, sum);
    }

    if(method->has_in)
        store_arguments(server, method_id, "InputArguments", &method->in_node, input_size,
                        input);
    if(method->has_out)
        store_arguments(server, method_id, "OutputArguments", &method->out_node,
                        output_size, output);
    return UA_STATUSCODE_GOOD;
}

/* Reads one method line,
 * "method <node-id> <kind> [busy=<ms>] [in=<node-id>] [out=<node-id>]", with
 * the kind echo, accept, sum, or sort. The optional nodes name the structure
 * Variables that hold the input and the output arguments of the last call.
 * The line attaches the simulated behavior to the Method node of the loaded
 * models. */
static UA_Boolean
parse_method(UA_Server *server, char *arguments) {
    SimMethod method;
    SimMethod *grown = NULL;
    char *save = NULL;
    char *node = strtok_r(arguments, " \t", &save);
    char *kind = strtok_r(NULL, " \t", &save);
    char *token = NULL;

    memset(&method, 0, sizeof(method));
    if(!node || !kind)
        return false;
    if(strcmp(kind, "echo") == 0)
        method.kind = METHOD_ECHO;
    else if(strcmp(kind, "accept") == 0)
        method.kind = METHOD_ACCEPT;
    else if(strcmp(kind, "sum") == 0)
        method.kind = METHOD_SUM;
    else if(strcmp(kind, "sort") == 0)
        method.kind = METHOD_SORT;
    else
        return false;

    for(token = strtok_r(NULL, " \t", &save); token; token = strtok_r(NULL, " \t", &save)) {
        char *end = NULL;
        UA_NodeId *target = NULL;
        if(strncmp(token, "busy=", 5) == 0) {
            method.busy_ms = strtod(token + 5, &end);
            if(end == token + 5 || *end != '\0' || method.busy_ms < 0.0)
                goto failed;
        } else if(strncmp(token, "in=", 3) == 0 && !method.has_in) {
            target = &method.in_node;
            method.has_in = UA_NodeId_parse(target, UA_STRING(token + 3)) == UA_STATUSCODE_GOOD;
            if(!method.has_in)
                goto failed;
        } else if(strncmp(token, "out=", 4) == 0 && !method.has_out) {
            target = &method.out_node;
            method.has_out = UA_NodeId_parse(target, UA_STRING(token + 4)) == UA_STATUSCODE_GOOD;
            if(!method.has_out)
                goto failed;
        } else {
            goto failed;
        }
    }

    if(UA_NodeId_parse(&method.node, UA_STRING(node)) != UA_STATUSCODE_GOOD)
        goto failed;
    if(!node_has_class(server, &method.node, UA_NODECLASS_METHOD) ||
       (method.has_in && !node_has_class(server, &method.in_node, UA_NODECLASS_VARIABLE)) ||
       (method.has_out && !node_has_class(server, &method.out_node, UA_NODECLASS_VARIABLE)) ||
       UA_Server_setMethodNodeCallback(server, method.node, method_callback) !=
           UA_STATUSCODE_GOOD)
        goto failed;

    grown = (SimMethod *)realloc(sim_methods, (sim_methods_size + 1) * sizeof(SimMethod));
    if(!grown)
        goto failed;
    sim_methods = grown;
    sim_methods[sim_methods_size++] = method;
    return true;

failed:
    UA_NodeId_clear(&method.node);
    UA_NodeId_clear(&method.in_node);
    UA_NodeId_clear(&method.out_node);
    return false;
}

/* Variable of the loaded models that shows the operating state, and the
 * values it takes in RUN and in STOP. */
static UA_NodeId cpu_mode_node;
static UA_Boolean cpu_mode_node_set = false;
static UA_Int32 cpu_run_value = 0;
static UA_Int32 cpu_stop_value = 0;

/* Writes the operating state into the Variable of the models that shows it. */
static void
publish_cpu_mode(UA_Server *server) {
    UA_Variant value;
    UA_Int32 mode = cpu_running ? cpu_run_value : cpu_stop_value;

    if(!cpu_mode_node_set)
        return;
    UA_Variant_setScalar(&value, &mode, &UA_TYPES[UA_TYPES_INT32]);
    if(UA_Server_writeValue(server, cpu_mode_node, value) != UA_STATUSCODE_GOOD)
        UA_LOG_WARNING(UA_Log_Stdout, UA_LOGCATEGORY_APPLICATION,
                       "cannot write the operating state to %N", cpu_mode_node);
}

/* Switches the CPU between RUN and STOP. Going to RUN is a restart: every
 * Variable returns to its start value, every signal starts over, and every
 * method instance is free again. */
static void
set_cpu_running(UA_Server *server, UA_Boolean running) {
    if(running == cpu_running)
        return;

    if(running) {
        restore_start_values(server);
        for(size_t i = 0; i < sim_signals_size; i++) {
            sim_signals[i].value = sim_signals[i].min;
            sim_signals[i].elapsed_ms = 0.0;
            write_signal(server, &sim_signals[i]);
        }
        for(size_t i = 0; i < sim_methods_size; i++)
            sim_methods[i].busy_until = 0;
        for(size_t i = 0; i < sim_on_delays_size; i++)
            sim_on_delays[i].elapsed_ms = 0.0;
    }

    cpu_running = running;
    publish_cpu_mode(server);
    UA_LOG_INFO(UA_Log_Stdout, UA_LOGCATEGORY_APPLICATION,
                "CPU operating state: %s", running ? "RUN" : "STOP");
}

/* Follows a write to the mode switch of the simulator. */
static void
on_switch_write(UA_Server *server, const UA_NodeId *session_id,
                void *session_context, const UA_NodeId *node_id,
                void *node_context, const UA_NumericRange *range,
                const UA_DataValue *data) {
    (void)session_id;
    (void)session_context;
    (void)node_id;
    (void)node_context;
    (void)range;

    if(data && data->hasValue &&
       UA_Variant_hasScalarType(&data->value, &UA_TYPES[UA_TYPES_BOOLEAN]))
        set_cpu_running(server, *(const UA_Boolean *)data->value.data);
}

/* Adds the mode switch of the simulator: a writable Boolean in a namespace
 * of its own, true for RUN and false for STOP. A device has a hardware
 * switch in its place; the node keeps the device namespaces untouched. */
static UA_Boolean
add_mode_switch(UA_Server *server) {
    static const UA_ValueSourceNotifications notifications = {NULL, on_switch_write};
    UA_UInt16 ns = UA_Server_addNamespace(server, SIM_CONTROL_NAMESPACE);
    UA_ObjectAttributes object = UA_ObjectAttributes_default;
    UA_VariableAttributes variable = UA_VariableAttributes_default;
    UA_NodeId object_id = UA_NODEID_STRING(ns, SIM_CONTROL_OBJECT);
    UA_NodeId switch_id = UA_NODEID_STRING(ns, SIM_CONTROL_SWITCH_ID);
    UA_Boolean run = true;

    object.displayName = UA_LOCALIZEDTEXT("", SIM_CONTROL_OBJECT);
    variable.displayName = UA_LOCALIZEDTEXT("", SIM_CONTROL_SWITCH);
    variable.dataType = UA_TYPES[UA_TYPES_BOOLEAN].typeId;
    variable.accessLevel = UA_ACCESSLEVELMASK_READ | UA_ACCESSLEVELMASK_WRITE;
    UA_Variant_setScalar(&variable.value, &run, &UA_TYPES[UA_TYPES_BOOLEAN]);

    return UA_Server_addObjectNode(server, object_id,
                                   UA_NODEID_NUMERIC(0, UA_NS0ID_OBJECTSFOLDER),
                                   UA_NODEID_NUMERIC(0, UA_NS0ID_ORGANIZES),
                                   UA_QUALIFIEDNAME(ns, SIM_CONTROL_OBJECT),
                                   UA_NODEID_NUMERIC(0, UA_NS0ID_BASEOBJECTTYPE),
                                   object, NULL, NULL) == UA_STATUSCODE_GOOD &&
           UA_Server_addVariableNode(server, switch_id, object_id,
                                     UA_NODEID_NUMERIC(0, UA_NS0ID_HASCOMPONENT),
                                     UA_QUALIFIEDNAME(ns, SIM_CONTROL_SWITCH),
                                     UA_NODEID_NUMERIC(0, UA_NS0ID_BASEDATAVARIABLETYPE),
                                     variable, NULL, NULL) == UA_STATUSCODE_GOOD &&
           UA_Server_setVariableNode_internalValueSource(server, switch_id, NULL,
                                                         &notifications) ==
               UA_STATUSCODE_GOOD;
}

/* Reads one line "operating-mode <node-id> run=<n> stop=<n>": the Variable
 * that shows the operating state and its values in RUN and in STOP. The line
 * also adds the mode switch. */
static UA_Boolean
parse_operating_mode(UA_Server *server, char *arguments) {
    char *save = NULL;
    char *node = strtok_r(arguments, " \t", &save);
    UA_Boolean has_run = false;
    UA_Boolean has_stop = false;
    UA_NodeClass node_class = UA_NODECLASS_UNSPECIFIED;

    if(!node || cpu_mode_node_set)
        return false;
    for(char *token = strtok_r(NULL, " \t", &save); token;
        token = strtok_r(NULL, " \t", &save)) {
        char *end = NULL;
        const char *text = strchr(token, '=');
        long number = text ? strtol(text + 1, &end, 10) : 0;
        if(!text || end == text + 1 || *end != '\0')
            return false;
        if(strncmp(token, "run=", 4) == 0) {
            cpu_run_value = (UA_Int32)number;
            has_run = true;
        } else if(strncmp(token, "stop=", 5) == 0) {
            cpu_stop_value = (UA_Int32)number;
            has_stop = true;
        } else {
            return false;
        }
    }
    if(!has_run || !has_stop)
        return false;

    if(UA_NodeId_parse(&cpu_mode_node, UA_STRING(node)) != UA_STATUSCODE_GOOD)
        return false;
    if(UA_Server_readNodeClass(server, cpu_mode_node, &node_class) !=
       UA_STATUSCODE_GOOD || node_class != UA_NODECLASS_VARIABLE ||
       !add_mode_switch(server)) {
        UA_NodeId_clear(&cpu_mode_node);
        return false;
    }
    cpu_mode_node_set = true;
    publish_cpu_mode(server);
    return true;
}

/* User accounts of the server and whether a client may log in without one. */
static UA_UsernamePasswordLogin *sim_logins = NULL;
static size_t sim_logins_size = 0;
static UA_Boolean sim_anonymous = true;
static UA_Boolean sim_access_configured = false;

/* Reads one line "user <name> <password>". */
static UA_Boolean
parse_user(char *arguments) {
    char *save = NULL;
    char *name = strtok_r(arguments, " \t", &save);
    char *password = strtok_r(NULL, " \t", &save);
    UA_UsernamePasswordLogin *grown = NULL;

    if(!name || !password || strtok_r(NULL, " \t", &save))
        return false;
    grown = (UA_UsernamePasswordLogin *)
        realloc(sim_logins, (sim_logins_size + 1) * sizeof(UA_UsernamePasswordLogin));
    if(!grown)
        return false;
    sim_logins = grown;
    sim_logins[sim_logins_size].username = UA_STRING_ALLOC(name);
    sim_logins[sim_logins_size].password = UA_BYTESTRING_ALLOC(password);
    sim_logins_size++;
    sim_access_configured = true;
    return true;
}

/* Reads one line "anonymous <yes|no>". */
static UA_Boolean
parse_anonymous(char *arguments) {
    char *save = NULL;
    char *answer = strtok_r(arguments, " \t", &save);

    if(!answer || strtok_r(NULL, " \t", &save))
        return false;
    if(strcmp(answer, "yes") == 0)
        sim_anonymous = true;
    else if(strcmp(answer, "no") == 0)
        sim_anonymous = false;
    else
        return false;
    sim_access_configured = true;
    return true;
}

/* Applies the user accounts to the server. A user name and password are
 * accepted on an endpoint without security as well, as a device does. */
static UA_Boolean
apply_access_control(UA_Server *server) {
    UA_ServerConfig *config = UA_Server_getConfig(server);

    if(!sim_access_configured)
        return true;
    config->allowNonePolicyPassword = true;
    return UA_AccessControl_default(config, sim_anonymous, NULL, sim_logins_size,
                                    sim_logins) == UA_STATUSCODE_GOOD;
}

/* Releases the recorded user accounts and the operating state node. */
static void
clear_cpu(void) {
    for(size_t i = 0; i < sim_logins_size; i++) {
        UA_String_clear(&sim_logins[i].username);
        UA_ByteString_clear(&sim_logins[i].password);
    }
    free(sim_logins);
    sim_logins = NULL;
    sim_logins_size = 0;
    if(cpu_mode_node_set)
        UA_NodeId_clear(&cpu_mode_node);
    cpu_mode_node_set = false;
}

/* Replaces every recorded start value with the value the Variable holds now,
 * so that a value set by the simulation file also returns after a restart. */
static void
refresh_start_values(UA_Server *server) {
    for(size_t i = 0; i < start_values_size; i++) {
        UA_Variant current;
        UA_Variant_init(&current);
        if(UA_Server_readValue(server, start_values[i].node, &current) ==
               UA_STATUSCODE_GOOD && current.type) {
            UA_Variant_clear(&start_values[i].value);
            start_values[i].value = current;
        } else {
            UA_Variant_clear(&current);
        }
    }
}

/* Reads one line "value <node-id> <number>": sets a Variable to a number
 * when the file is read; the number becomes the start value of the Variable. */
static UA_Boolean
parse_value(UA_Server *server, char *arguments) {
    char *save = NULL;
    char *node_text = strtok_r(arguments, " \t", &save);
    char *number_text = strtok_r(NULL, " \t", &save);
    char *end = NULL;
    UA_NodeId node = UA_NODEID_NULL;
    double number = 0.0;
    UA_Boolean good = false;

    if(!node_text || !number_text || strtok_r(NULL, " \t", &save))
        return false;
    number = strtod(number_text, &end);
    if(end == number_text || *end != '\0' || number != number)
        return false;
    if(UA_NodeId_parse(&node, UA_STRING(node_text)) != UA_STATUSCODE_GOOD)
        return false;
    good = node_has_class(server, &node, UA_NODECLASS_VARIABLE) &&
           write_number(server, &node, number);
    UA_NodeId_clear(&node);
    if(good)
        refresh_start_values(server);
    return good;
}

/* Limits of the running server that a line "limit <name> <number>" sets. The
 * session count and the interval limits belong to the server configuration;
 * a continuation point count is a value of the Server object that the
 * configuration file cannot set. */
typedef enum { LIMIT_SESSIONS, LIMIT_PUBLISHING_MIN, LIMIT_SAMPLING_MIN,
               LIMIT_CONTINUATION } LimitKind;

static const struct {
    const char *name;
    LimitKind kind;
    UA_UInt32 node;
} sim_limits[] = {
    {"max-sessions", LIMIT_SESSIONS, 0},
    {"publishing-interval-min", LIMIT_PUBLISHING_MIN, 0},
    {"sampling-interval-min", LIMIT_SAMPLING_MIN, 0},
    {"max-browse-continuation-points", LIMIT_CONTINUATION,
     UA_NS0ID_SERVER_SERVERCAPABILITIES_MAXBROWSECONTINUATIONPOINTS},
    {"max-query-continuation-points", LIMIT_CONTINUATION,
     UA_NS0ID_SERVER_SERVERCAPABILITIES_MAXQUERYCONTINUATIONPOINTS},
    {"max-history-continuation-points", LIMIT_CONTINUATION,
     UA_NS0ID_SERVER_SERVERCAPABILITIES_MAXHISTORYCONTINUATIONPOINTS},
};

/* Smallest interval that the server accepts. */
#define SIM_MIN_INTERVAL_MS 5.0

static UA_Boolean
parse_limit(UA_Server *server, char *arguments) {
    char *save = NULL;
    char *name = strtok_r(arguments, " \t", &save);
    char *number_text = strtok_r(NULL, " \t", &save);
    char *end = NULL;
    UA_ServerConfig *config = UA_Server_getConfig(server);
    double number = 0.0;
    size_t found = sizeof(sim_limits) / sizeof(sim_limits[0]);

    if(!name || !number_text || strtok_r(NULL, " \t", &save))
        return false;
    number = strtod(number_text, &end);
    if(end == number_text || *end != '\0' || number != number)
        return false;
    for(size_t i = 0; i < sizeof(sim_limits) / sizeof(sim_limits[0]); i++) {
        if(strcmp(name, sim_limits[i].name) == 0)
            found = i;
    }
    if(found == sizeof(sim_limits) / sizeof(sim_limits[0]))
        return false;

    switch(sim_limits[found].kind) {
    case LIMIT_SESSIONS:
        if(number < 1.0 || number > 65535.0 || number != (double)(UA_UInt16)number)
            return false;
        config->maxSessions = (UA_UInt16)number;
        return true;
    case LIMIT_PUBLISHING_MIN:
        if(number < SIM_MIN_INTERVAL_MS || number > config->publishingIntervalLimits.max)
            return false;
        config->publishingIntervalLimits.min = number;
        return true;
    case LIMIT_SAMPLING_MIN:
        if(number < SIM_MIN_INTERVAL_MS || number > config->samplingIntervalLimits.max)
            return false;
        config->samplingIntervalLimits.min = number;
        return true;
    case LIMIT_CONTINUATION: {
        UA_UInt16 count = 0;
        UA_Variant value;
        if(number < 0.0 || number > 65535.0 || number != (double)(UA_UInt16)number)
            return false;
        count = (UA_UInt16)number;
        UA_Variant_setScalar(&value, &count, &UA_TYPES[UA_TYPES_UINT16]);
        return UA_Server_writeValue(server, UA_NODEID_NUMERIC(0, sim_limits[found].node),
                                    value) == UA_STATUSCODE_GOOD;
    }
    }
    return false;
}

/* Deepest nesting of "include" lines; a file that includes itself fails. */
#define SIM_MAX_INCLUDE_DEPTH 8

/* Longest path of an included file. */
#define SIM_PATH_SIZE 4096

/* Joins the name of an included file to the directory of the file that
 * includes it. An absolute name is kept. Returns false when it does not fit. */
static UA_Boolean
resolve_include(const char *including, const char *name, char *out, size_t size) {
    const char *slash = strrchr(including, '/');
    int written = 0;

    if(name[0] == '/' || !slash)
        written = snprintf(out, size, "%s", name);
    else
        written = snprintf(out, size, "%.*s/%s", (int)(slash - including), including, name);
    return written > 0 && (size_t)written < size;
}

/* Reads one simulation file. Each line, of any length, is empty, a comment
 * starting with '#', or an "include", "limit", "value", "cycle", "signal",
 * "method", "pack", "count", "on-delay", "alarm", "event", "field", "queue",
 * "operating-mode", "user", or "anonymous" line. Returns false and logs the line number at the
 * first line that cannot be applied. */
static UA_Boolean
read_simulation_file(UA_Server *server, const char *path, unsigned depth) {
    char *line = NULL;
    size_t line_capacity = 0;
    unsigned long line_number = 0;
    UA_Boolean good = true;
    FILE *fp = fopen(path, "r");

    if(!fp) {
        UA_LOG_FATAL(UA_Log_Stdout, UA_LOGCATEGORY_APPLICATION,
                     "cannot open %s: %s", path, strerror(errno));
        return false;
    }

    while(good && getline(&line, &line_capacity, fp) != -1) {
        char *save = NULL;
        char *keyword = NULL;

        line_number++;
        line[strcspn(line, "\r\n")] = '\0';
        keyword = strtok_r(line, " \t", &save);
        if(!keyword || keyword[0] == '#')
            continue;

        if(strcmp(keyword, "include") == 0) {
            char *name = strtok_r(NULL, " \t", &save);
            char resolved[SIM_PATH_SIZE];
            good = name && !strtok_r(NULL, " \t", &save) &&
                   depth < SIM_MAX_INCLUDE_DEPTH &&
                   resolve_include(path, name, resolved, sizeof(resolved)) &&
                   read_simulation_file(server, resolved, depth + 1);
        } else if(strcmp(keyword, "limit") == 0) {
            good = parse_limit(server, save);
        } else if(strcmp(keyword, "value") == 0) {
            good = parse_value(server, save);
        } else if(strcmp(keyword, "cycle") == 0) {
            char *text = strtok_r(NULL, " \t", &save);
            char *end = NULL;
            double cycle = text ? strtod(text, &end) : 0.0;
            good = text && end != text && *end == '\0' && cycle > 0.0;
            if(good)
                sim_cycle_ms = cycle;
        } else if(strcmp(keyword, "signal") == 0) {
            good = parse_signal(server, save);
        } else if(strcmp(keyword, "method") == 0) {
            good = parse_method(server, save);
        } else if(strcmp(keyword, "pack") == 0) {
            good = parse_pack(server, save, false);
        } else if(strcmp(keyword, "count") == 0) {
            good = parse_pack(server, save, true);
        } else if(strcmp(keyword, "on-delay") == 0) {
            good = parse_on_delay(server, save);
        } else if(strcmp(keyword, "alarm") == 0) {
            good = parse_alarm(server, save, true);
        } else if(strcmp(keyword, "event") == 0) {
            good = parse_alarm(server, save, false);
        } else if(strcmp(keyword, "queue") == 0) {
            good = parse_queue(server, save);
        } else if(strcmp(keyword, "field") == 0) {
            good = parse_field(server, save);
        } else if(strcmp(keyword, "operating-mode") == 0) {
            good = parse_operating_mode(server, save);
        } else if(strcmp(keyword, "user") == 0) {
            good = parse_user(save);
        } else if(strcmp(keyword, "anonymous") == 0) {
            good = parse_anonymous(save);
        } else {
            good = false;
        }
    }
    /* getline also returns -1 when reading fails, as it does for a directory. */
    if(good && ferror(fp)) {
        UA_LOG_FATAL(UA_Log_Stdout, UA_LOGCATEGORY_APPLICATION,
                     "cannot read %s: %s", path, strerror(errno));
        free(line);
        fclose(fp);
        return false;
    }
    free(line);
    fclose(fp);

    if(!good) {
        UA_LOG_FATAL(UA_Log_Stdout, UA_LOGCATEGORY_APPLICATION,
                     "%s line %lu cannot be applied", path, line_number);
        return false;
    }
    return true;
}

/* Reads the simulation file with the files it includes, then applies the user
 * accounts that the files name. */
static UA_Boolean
load_simulation(UA_Server *server, const char *path) {
    if(!read_simulation_file(server, path, 0))
        return false;
    bind_queues();
    if(!apply_access_control(server)) {
        UA_LOG_FATAL(UA_Log_Stdout, UA_LOGCATEGORY_APPLICATION,
                     "cannot apply the user accounts of %s", path);
        return false;
    }

    UA_LOG_INFO(UA_Log_Stdout, UA_LOGCATEGORY_APPLICATION,
                "simulating %lu signals every %.0f ms, %lu methods, %lu alarms",
                (unsigned long)sim_signals_size, sim_cycle_ms,
                (unsigned long)sim_methods_size, (unsigned long)sim_alarms_size);
    return true;
}

/* Releases the recorded signals, methods, logic elements, and alarms. */
static void
clear_simulation(void) {
    for(size_t i = 0; i < sim_signals_size; i++)
        UA_NodeId_clear(&sim_signals[i].node);
    free(sim_signals);
    sim_signals = NULL;
    sim_signals_size = 0;

    for(size_t i = 0; i < sim_methods_size; i++) {
        UA_NodeId_clear(&sim_methods[i].node);
        UA_NodeId_clear(&sim_methods[i].in_node);
        UA_NodeId_clear(&sim_methods[i].out_node);
    }
    free(sim_methods);
    sim_methods = NULL;
    sim_methods_size = 0;

    for(size_t i = 0; i < sim_packs_size; i++) {
        UA_NodeId_clear(&sim_packs[i].target);
        for(size_t bit = 0; bit < sim_packs[i].bits_size; bit++)
            UA_NodeId_clear(&sim_packs[i].bits[bit]);
    }
    free(sim_packs);
    sim_packs = NULL;
    sim_packs_size = 0;

    for(size_t i = 0; i < sim_on_delays_size; i++) {
        UA_NodeId_clear(&sim_on_delays[i].input);
        UA_NodeId_clear(&sim_on_delays[i].output);
        UA_NodeId_clear(&sim_on_delays[i].delay_node);
        UA_NodeId_clear(&sim_on_delays[i].elapsed_node);
    }
    free(sim_on_delays);
    sim_on_delays = NULL;
    sim_on_delays_size = 0;

    for(size_t i = 0; i < sim_alarms_size; i++) {
        UA_NodeId_clear(&sim_alarms[i].type);
        UA_NodeId_clear(&sim_alarms[i].source);
        UA_NodeId_clear(&sim_alarms[i].trigger);
        UA_NodeId_clear(&sim_alarms[i].condition);
        free(sim_alarms[i].message);
        for(size_t k = 0; k < sim_alarms[i].fields_size; k++) {
            UA_QualifiedName_clear(&sim_alarms[i].fields[k].key);
            UA_Variant_clear(&sim_alarms[i].fields[k].value);
        }
        free(sim_alarms[i].fields);
    }
    free(sim_alarms);
    sim_alarms = NULL;
    sim_alarms_size = 0;

    for(size_t i = 0; i < sim_queues_size; i++) {
        UA_NodeId_clear(&sim_queues[i].max_node);
        UA_NodeId_clear(&sim_queues[i].hysteresis_node);
        UA_NodeId_clear(&sim_queues[i].current_node);
        UA_NodeId_clear(&sim_queues[i].outstanding_node);
        UA_NodeId_clear(&sim_queues[i].source);
        UA_NodeId_clear(&sim_queues[i].overload_trigger);
    }
    free(sim_queues);
    sim_queues = NULL;
    sim_queues_size = 0;
}

int
main(int argc, char **argv) {
    UA_ByteString config = UA_BYTESTRING_NULL;
    UA_Server *server = NULL;
    UA_StatusCode status = UA_STATUSCODE_GOOD;
    const char *simulation_path = NULL;
    int option = 0;

    while((option = getopt(argc, argv, "s:")) != -1) {
        if(option == 's')
            simulation_path = optarg;
        else
            optind = argc;
    }
    if(optind >= argc) {
        fprintf(stderr,
                "usage: %s [-s <simulation-file>] <server-config.json5> [<nodeset2.xml> ...]\n",
                argv[0]);
        return EXIT_USAGE;
    }

    config = read_file(argv[optind]);
    if(config.length == 0)
        return EXIT_FAILURE;

    server = UA_Server_newFromFile(config);
    UA_ByteString_clear(&config);
    if(!server) {
        UA_LOG_FATAL(UA_Log_Stdout, UA_LOGCATEGORY_APPLICATION,
                     "invalid server configuration in %s", argv[optind]);
        return EXIT_FAILURE;
    }

    for(int i = optind + 1; i < argc; i++) {
        status = UA_Server_loadNodeset(server, argv[i], NULL);
        if(UA_StatusCode_isBad(status)) {
            UA_LOG_FATAL(UA_Log_Stdout, UA_LOGCATEGORY_APPLICATION,
                         "cannot load NodeSet %s: %s", argv[i],
                         UA_StatusCode_name(status));
            UA_Server_delete(server);
            return EXIT_FAILURE;
        }
    }

    set_build_identity(server);
    prepare_variables(server);
    log_namespaces(server);

    if(simulation_path) {
        srand((unsigned int)time(NULL));
        if(!load_simulation(server, simulation_path) ||
           UA_Server_addRepeatedCallback(server, simulation_step, NULL,
                                         sim_cycle_ms, NULL) != UA_STATUSCODE_GOOD) {
            clear_simulation();
            clear_cpu();
            clear_start_values();
            clear_value_links();
            UA_Server_delete(server);
            return EXIT_FAILURE;
        }
    }

    status = UA_Server_runUntilInterrupt(server);

    /* The start values hold structures whose data types belong to the server,
     * so they are released before the server. */
    clear_simulation();
    clear_cpu();
    clear_start_values();
    clear_value_links();
    status |= UA_Server_delete(server);

    return status == UA_STATUSCODE_GOOD ? EXIT_SUCCESS : EXIT_FAILURE;
}
