package org.swifttla.conformance;

import java.io.BufferedWriter;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.LinkedHashMap;
import java.util.Map;

import tla2sany.semantic.SemanticNode;
import tlc2.tool.Action;
import tlc2.tool.TLCState;
import tlc2.util.BitVector;
import tlc2.util.IStateWriter;

/** TLC v1.8.0 transport-only writer for the bounded conformance spike. */
public final class LosslessStateWriter implements IStateWriter {
    private static final String SCHEMA = "swifttla.tlc.graph-events";
    private static final int VERSION = 1;
    private static final String OUTPUT_PROPERTY = "swifttla.tlc.graph.path";
    private static final String PROVENANCE_PROPERTY = "swifttla.tlc.graph.provenance";
    private static final String RUN_ID_PROPERTY = "swifttla.tlc.graph.run-id";
    private static final String CASE_ID_PROPERTY = "swifttla.tlc.graph.case-id";

    private final Path outputPath;
    private final BufferedWriter output;
    private final MessageDigest bodyDigest;
    private final String provenance;
    private final String runId;
    private final String caseId;
    private final Map<String, Integer> counts = new LinkedHashMap<>();
    private long sequence;
    private boolean closed;

    public LosslessStateWriter() {
        try {
            outputPath = Path.of(required(OUTPUT_PROPERTY)).toAbsolutePath().normalize();
            provenance = jsonObject(required(PROVENANCE_PROPERTY), PROVENANCE_PROPERTY);
            runId = required(RUN_ID_PROPERTY);
            caseId = required(CASE_ID_PROPERTY);
            Files.createDirectories(outputPath.getParent());
            output = Files.newBufferedWriter(outputPath, StandardCharsets.UTF_8);
            bodyDigest = MessageDigest.getInstance("SHA-256");
            emit("header", "writer.header", "\"provenance\":" + provenance);
            Runtime.getRuntime().addShutdownHook(new Thread(this::close, "swifttla-graph-writer-close"));
        } catch (IOException error) {
            throw new UncheckedIOException("cannot create TLC graph event stream", error);
        } catch (NoSuchAlgorithmException error) {
            throw new IllegalStateException("SHA-256 is unavailable", error);
        }
    }

    @Override
    public synchronized void writeState(TLCState state) {
        emit("initial", "writeState.initial", "\"state\":" + state(state));
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
        transition("writeState.actionPredicate", source, target, flags, action, quote(location(predicate)), "excluded");
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
        output.flush();
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
        if (action == null || !action.isNamed() || action.getName() == null || action.getName().toString().isBlank()) {
            unsupported(callback, "callback lacks a stable named Action");
            return;
        }
        String actionJson = "{\"name\":" + quote(action.getName().toString())
                + ",\"location\":" + quote(action.getLocation()) + ",\"named\":true}";
        String flagsJson = "{\"raw\":" + Integer.toUnsignedString(Short.toUnsignedInt(flags))
                + ",\"seen\":" + ((flags & IStateWriter.IsSeen) == IStateWriter.IsSeen)
                + ",\"notInModel\":" + ((flags & IStateWriter.IsNotInModel) == IStateWriter.IsNotInModel) + "}";
        emit("transition", callback, "\"source\":" + state(source)
                + ",\"target\":" + state(target)
                + ",\"action\":" + actionJson
                + ",\"stateFlags\":" + flagsJson
                + ",\"visualization\":\"none\""
                + ",\"predicateLocation\":" + predicateLocation
                + ",\"reachable\":" + quote(reachable));
    }

    private void unsupported(String callback, String reason) {
        emit("unsupported", callback, "\"reason\":" + quote(reason));
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
                    .append(",\"tla\":").append(quote(value))
                    .append(",\"tlaSha256\":").append(quote(sha256(value))).append('}');
        }
        return "{\"fingerprint\":" + quote(Long.toUnsignedString(state.fingerPrint()))
                + ",\"level\":" + state.getLevel() + ",\"bindings\":" + bindings + "]}";
    }

    private void emit(String type, String callback, String fields) {
        ensureOpen();
        String line = base(type, callback) + "," + fields + "}";
        try {
            byte[] bytes = (line + "\n").getBytes(StandardCharsets.UTF_8);
            output.write(line);
            output.write('\n');
            output.flush();
            bodyDigest.update(bytes);
            counts.merge(type, 1, Integer::sum);
            sequence++;
        } catch (IOException error) {
            throw new UncheckedIOException("cannot append TLC graph event", error);
        }
    }

    private String base(String type, String callback) {
        return "{\"schema\":\"" + SCHEMA + "\",\"version\":" + VERSION
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

    private static String jsonObject(String value, String property) {
        String trimmed = value.trim();
        if (!trimmed.startsWith("{") || !trimmed.endsWith("}")) {
            throw new IllegalStateException(property + " must be a JSON object");
        }
        return trimmed;
    }

    private static String location(SemanticNode node) {
        return node == null ? "" : String.valueOf(node.getLocation());
    }

    private static String sha256(String value) {
        try {
            return hex(MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException error) {
            throw new IllegalStateException("SHA-256 is unavailable", error);
        }
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
