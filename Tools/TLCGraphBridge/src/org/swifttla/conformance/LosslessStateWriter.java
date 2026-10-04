package org.swifttla.conformance;

import java.io.BufferedWriter;
import java.io.BufferedOutputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.io.OutputStreamWriter;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.DigestOutputStream;
import java.security.NoSuchAlgorithmException;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.List;
import java.util.stream.Collectors;
import java.util.zip.GZIPOutputStream;

import tla2sany.semantic.SemanticNode;
import tlc2.TLCGlobals;
import tlc2.tool.Action;
import tlc2.tool.TLCState;
import tlc2.util.BitVector;
import tlc2.util.IStateWriter;

/** TLC v1.8.0 graph-event writer. */
public final class LosslessStateWriter implements IStateWriter {
    private static final String SCHEMA = "swifttla.tlc.graph-events";
    private static final int VERSION = 3;
    private static final String OUTPUT_PROPERTY = "swifttla.tlc.graph.path";
    private static final String RUN_ID_PROPERTY = "swifttla.tlc.graph.run-id";
    private static final String CASE_ID_PROPERTY = "swifttla.tlc.graph.case-id";
    private static final String COMPACT_GZIP_PROPERTY = "swifttla.tlc.graph.compact-gzip";

    private final Path outputPath;
    private final BufferedWriter output;
    private final DataOutputStream binaryOutput;
    private final DigestOutputStream digestOutput;
    private final MessageDigest bodyDigest;
    private final String runId;
    private final String caseId;
    private final boolean compactGzip;
    private final boolean binary;
    private final Map<String, Integer> binaryActions = new LinkedHashMap<>();
    private long binaryStates;
    private long binaryInitials;
    private long binaryEdges;
    private long binaryExcluded;
    private long binaryUnsupported;
    private final Map<String, Integer> counts = new LinkedHashMap<>();
    private final InstanceActions instanceActions = new InstanceActions();
    private long sequence;
    private boolean closed;

    public LosslessStateWriter() {
        try {
            outputPath = Path.of(required(OUTPUT_PROPERTY)).toAbsolutePath().normalize();
            runId = required(RUN_ID_PROPERTY);
            caseId = required(CASE_ID_PROPERTY);
            compactGzip = Boolean.getBoolean(COMPACT_GZIP_PROPERTY);
            binary = outputPath.toString().endsWith(".bin") || outputPath.toString().endsWith(".bin.gz");
            Files.createDirectories(outputPath.getParent());
            bodyDigest = MessageDigest.getInstance("SHA-256");
            if (binary) {
                var stream = Files.newOutputStream(outputPath);
                if (outputPath.toString().endsWith(".bin.gz")) {
                    stream = new GZIPOutputStream(stream, 65536);
                }
                digestOutput = new DigestOutputStream(
                        new BufferedOutputStream(stream, 1 << 20), bodyDigest);
                binaryOutput = new DataOutputStream(digestOutput);
                output = null;
                binaryOutput.write("STLAGRF2".getBytes(StandardCharsets.US_ASCII));
                binaryOutput.writeByte(1);
                binaryString(caseId);
                binaryString(runId);
            } else if (compactGzip) {
                digestOutput = null;
                binaryOutput = null;
                GZIPOutputStream zipped = new GZIPOutputStream(Files.newOutputStream(outputPath), 65536, true);
                output = new BufferedWriter(new OutputStreamWriter(zipped, StandardCharsets.UTF_8), 65536);
            } else {
                digestOutput = null;
                binaryOutput = null;
                output = Files.newBufferedWriter(outputPath, StandardCharsets.UTF_8);
            }
            if (!binary) {
                emit("header", "writer.header", "");
            }
            Runtime.getRuntime().addShutdownHook(new Thread(this::close, "swifttla-graph-writer-close"));
        } catch (IOException error) {
            throw new UncheckedIOException("cannot create TLC graph event stream", error);
        } catch (NoSuchAlgorithmException error) {
            throw new IllegalStateException("SHA-256 is unavailable", error);
        }
    }

    @Override
    public synchronized void writeState(TLCState state) {
        if (binary) {
            try {
                binaryState(state, true);
            } catch (IOException error) {
                throw new UncheckedIOException("cannot append TLC initial state", error);
            }
        } else {
            emit("initial", "writeState.initial", "\"state\":" + state(state));
        }
    }

    @Override
    public synchronized void writeState(TLCState source, TLCState target, short flags) {
        unsupported("writeState.unlabeled", "callback has no Action identity");
    }

    @Override
    public synchronized void writeState(TLCState source, TLCState target, short flags, Action action) {
        transition("writeState.action", source, target, flags, action, "null", "reachable");
    }

    @Override
    public synchronized void writeState(TLCState source, TLCState target, short flags, Action action, SemanticNode predicate) {
        transition("writeState.actionPredicate", source, target, flags, action,
                binary ? location(predicate) : quote(location(predicate)), "excluded");
    }

    @Override
    public synchronized void writeState(TLCState source, TLCState target, short flags, Visualization visualization) {
        unsupported("writeState.visualization", "callback has no Action identity: " + visualization.name());
    }

    @Override
    public synchronized void writeState(TLCState source, TLCState target, BitVector checks, int from, int length, short flags) {
        unsupported("writeState.actionChecks", "BitVector action-check callback is outside the bounded relation");
    }

    @Override
    public synchronized void writeState(TLCState source, TLCState target, BitVector checks, int from, int length, short flags, Visualization visualization) {
        unsupported("writeState.actionChecksVisualization", "BitVector action-check callback is outside the bounded relation");
    }

    @Override
    public synchronized void close() {
        if (closed) {
            return;
        }
        try {
            if (binary) {
                digestOutput.on(false);
                byte[] bodyHash = bodyDigest.digest();
                binaryOutput.writeByte(255);
                binaryOutput.writeLong(binaryStates);
                binaryOutput.writeLong(binaryInitials);
                binaryOutput.writeLong(binaryEdges);
                binaryOutput.writeLong(binaryExcluded);
                binaryOutput.writeLong(binaryUnsupported);
                binaryOutput.writeLong(0);
                binaryOutput.writeLong(0);
                binaryOutput.writeLong(0);
                binaryOutput.writeByte(0);
                binaryOutput.write(bodyHash);
                binaryOutput.close();
                closed = true;
                return;
            }
            String bodyHash = hex(bodyDigest.digest());
            String footer = base("footer", "writer.close")
                    + ",\"status\":\"closed\",\"counts\":" + countsJson()
                    + ",\"lastBodySeq\":" + (sequence - 1)
                    + ",\"bodySha256\":" + quote(bodyHash) + "}";
            output.write(footer);
            output.write('\n');
            output.flush();
            output.close();
            closed = true;
        } catch (IOException error) {
            throw new UncheckedIOException("cannot close TLC graph event stream", error);
        }
    }

    @Override
    public synchronized void snapshot() throws IOException {
        if (binary) {
            binaryOutput.flush();
        } else {
            output.flush();
        }
    }

    @Override
    public String getDumpFileName() {
        return outputPath.toString();
    }

    @Override
    public boolean isNoop() {
        return false;
    }

    @Override
    public boolean isDot() {
        return false;
    }

    @Override
    public boolean isConstrained() {
        return true;
    }

    private void transition(String callback, TLCState source, TLCState target, short flags, Action action,
                            String predicateLocation, String reachable) {
        final List<Action> resolved;
        try {
            resolved = callback.equals("writeState.actionPredicate") ? List.of()
                    : instanceActions.matching(TLCGlobals.mainChecker == null ? null : TLCGlobals.mainChecker.tool,
                            action, source, target);
            if (resolved.stream().anyMatch(candidate -> !candidate.isNamed())) {
                throw new IllegalArgumentException("callback lacks a stable named Action");
            }
        } catch (RuntimeException error) {
            unsupported(callback, "Action resolution failed: " + error.getMessage());
            return;
        }
        if (binary) {
            try {
                if (callback.equals("writeState.actionPredicate")) {
                    if ((flags & IStateWriter.IsNotInModel) != IStateWriter.IsNotInModel
                            || (flags & IStateWriter.IsSeen) == IStateWriter.IsSeen) {
                        throw new IllegalArgumentException("invalid excluded transition flags");
                    }
                    binaryOutput.writeByte(4);
                    binaryOutput.writeLong(source.fingerPrint());
                    binaryOutput.writeLong(target.fingerPrint());
                    binaryOutput.writeShort(Short.toUnsignedInt(flags));
                    binaryString(predicateLocation);
                    binaryExcluded++;
                    return;
                }
                if ((flags & IStateWriter.IsNotInModel) == IStateWriter.IsNotInModel || resolved.isEmpty()) {
                    throw new IllegalArgumentException("invalid reachable transition");
                }
                if ((flags & IStateWriter.IsSeen) != IStateWriter.IsSeen) {
                    binaryState(target, false);
                }
                for (Action resolvedAction : resolved) {
                    int actionId = binaryAction(resolvedAction);
                    binaryOutput.writeByte(3);
                    binaryOutput.writeLong(source.fingerPrint());
                    binaryOutput.writeInt(actionId);
                    binaryOutput.writeLong(target.fingerPrint());
                    binaryEdges++;
                }
            } catch (IOException error) {
                throw new UncheckedIOException("cannot append TLC transition", error);
            }
            return;
        }
        String flagsJson = "{\"raw\":" + Integer.toUnsignedString(Short.toUnsignedInt(flags))
                + ",\"seen\":" + ((flags & IStateWriter.IsSeen) == IStateWriter.IsSeen)
                + ",\"notInModel\":" + ((flags & IStateWriter.IsNotInModel) == IStateWriter.IsNotInModel) + "}";
        boolean referenceTarget = compactGzip && (callback.equals("writeState.actionPredicate")
                || (flags & IStateWriter.IsSeen) == IStateWriter.IsSeen);
        emit("transition", callback, "\"source\":" + (compactGzip ? stateReference(source) : state(source))
                + ",\"target\":" + (referenceTarget ? stateReference(target) : state(target))
                + ",\"action\":" + action(action)
                + ",\"resolvedActions\":" + resolved.stream().map(LosslessStateWriter::action)
                    .collect(Collectors.joining(",", "[", "]"))
                + ",\"stateFlags\":" + flagsJson
                + ",\"visualization\":\"none\""
                + ",\"predicateLocation\":" + predicateLocation
                + ",\"reachable\":" + quote(reachable));
    }

    private static String action(Action action) {
        return "{\"name\":" + quote(action.getName().toString())
                + ",\"location\":" + quote(action.getLocation()) + ",\"named\":" + action.isNamed() + "}";
    }

    private void unsupported(String callback, String reason) {
        if (binary) {
            try {
                binaryOutput.writeByte(5);
                binaryString(callback);
                binaryString(reason);
                binaryUnsupported++;
            } catch (IOException error) {
                throw new UncheckedIOException("cannot append TLC observation", error);
            }
        } else {
            emit("unsupported", callback, "\"reason\":" + quote(reason));
        }
    }

    private void binaryState(TLCState state, boolean initial) throws IOException {
        binaryOutput.writeByte(2);
        binaryOutput.writeLong(state.fingerPrint());
        binaryOutput.writeByte(initial ? 1 : 0);
        byte[] key = CanonicalBinaryState.encode(state);
        binaryOutput.writeInt(key.length);
        binaryOutput.write(key);
        binaryStates++;
        if (initial) {
            binaryInitials++;
        }
    }

    private int binaryAction(Action action) throws IOException {
        String name = action.getName().toString();
        String location = action.getLocation();
        String key = name + '\0' + location;
        Integer existing = binaryActions.get(key);
        if (existing != null) {
            return existing;
        }
        int id = binaryActions.size();
        binaryActions.put(key, id);
        binaryOutput.writeByte(1);
        binaryOutput.writeInt(id);
        binaryString(name);
        binaryString(location);
        return id;
    }

    private void binaryString(String value) throws IOException {
        byte[] bytes = value.getBytes(StandardCharsets.UTF_8);
        binaryOutput.writeInt(bytes.length);
        binaryOutput.write(bytes);
    }

    private String state(TLCState state) {
        StringBuilder bindings = new StringBuilder("[");
        String[] names = state.getVarsAsStrings();
        for (int index = 0; index < names.length; index++) {
            if (index > 0) {
                bindings.append(',');
            }
            String value = String.valueOf(state.lookup(names[index]));
            bindings.append("{\"ordinal\":").append(index)
                    .append(",\"name\":").append(quote(names[index]))
                    .append(",\"tla\":").append(quote(value)).append('}');
        }
        return "{\"fingerprint\":" + quote(Long.toUnsignedString(state.fingerPrint()))
                + ",\"level\":" + state.getLevel() + ",\"bindings\":" + bindings + "]}";
    }

    private static String stateReference(TLCState state) {
        return "{\"fingerprint\":" + quote(Long.toUnsignedString(state.fingerPrint()))
                + ",\"level\":" + state.getLevel() + "}";
    }

    private void emit(String type, String callback, String fields) {
        ensureOpen();
        String line = base(type, callback) + (fields.isEmpty() ? "}" : "," + fields + "}");
        try {
            byte[] bytes = (line + "\n").getBytes(StandardCharsets.UTF_8);
            output.write(line);
            output.write('\n');
            bodyDigest.update(bytes);
            counts.merge(type, 1, Integer::sum);
            sequence++;
        } catch (IOException error) {
            throw new UncheckedIOException("cannot append TLC graph event", error);
        }
    }

    private String base(String type, String callback) {
        return "{\"schema\":\"" + SCHEMA + "\",\"version\":" + (compactGzip ? 4 : VERSION)
                + ",\"type\":" + quote(type) + ",\"callback\":" + quote(callback)
                + ",\"seq\":" + sequence + ",\"runId\":" + quote(runId)
                + ",\"caseId\":" + quote(caseId);
    }

    private String countsJson() {
        StringBuilder json = new StringBuilder("{");
        boolean first = true;
        for (Map.Entry<String, Integer> entry : counts.entrySet()) {
            if (!first) {
                json.append(',');
            }
            json.append(quote(entry.getKey())).append(':').append(entry.getValue());
            first = false;
        }
        return json.append('}').toString();
    }

    private void ensureOpen() {
        if (closed) {
            throw new IllegalStateException("TLC wrote after the graph event stream closed");
        }
    }

    private static String required(String property) {
        String value = System.getProperty(property);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException("missing required system property: " + property);
        }
        return value;
    }

    private static String location(SemanticNode node) {
        return node == null ? "" : String.valueOf(node.getLocation());
    }

    private static String hex(byte[] bytes) {
        StringBuilder result = new StringBuilder(bytes.length * 2);
        for (byte value : bytes) {
            result.append(String.format("%02x", value));
        }
        return result.toString();
    }

    private static String quote(String value) {
        StringBuilder json = new StringBuilder("\"");
        for (int index = 0; index < value.length(); index++) {
            char character = value.charAt(index);
            switch (character) {
                case '\\': json.append("\\\\"); break;
                case '\"': json.append("\\\""); break;
                case '\b': json.append("\\b"); break;
                case '\f': json.append("\\f"); break;
                case '\n': json.append("\\n"); break;
                case '\r': json.append("\\r"); break;
                case '\t': json.append("\\t"); break;
                default:
                    if (character < 0x20) {
                        json.append(String.format("\\u%04x", (int) character));
                    } else {
                        json.append(character);
                    }
            }
        }
        return json.append('\"').toString();
    }
}
