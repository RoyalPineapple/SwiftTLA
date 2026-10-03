package org.swifttla.conformance;

import java.io.BufferedOutputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.io.Writer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

/** Captures each pinned TLC PrintT/Print call separately from TLC progress output. */
public final class TLCEvaluationOutput extends Writer {
    private static final String OUTPUT_PROPERTY = "swifttla.tlc.evaluation.path";
    private static final byte[] MAGIC = "STLAOUT1".getBytes(StandardCharsets.US_ASCII);

    private final DataOutputStream output;
    private long count;
    private boolean closed;

    private TLCEvaluationOutput(Path path) throws IOException {
        Files.createDirectories(path.getParent());
        output = new DataOutputStream(new BufferedOutputStream(Files.newOutputStream(path), 65536));
        output.write(MAGIC);
        output.writeByte(1);
    }

    public static void main(String[] args) throws Exception {
        String configured = System.getProperty(OUTPUT_PROPERTY);
        if (configured == null || configured.isBlank()) {
            throw new IllegalArgumentException("missing " + OUTPUT_PROPERTY);
        }
        Path path = Path.of(configured).toAbsolutePath().normalize();
        TLCEvaluationOutput capture = new TLCEvaluationOutput(path);
        tlc2.module.TLC.OUTPUT = capture;
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            try {
                capture.close();
            } catch (IOException error) {
                System.err.println("cannot complete TLC evaluation output: " + error);
            }
        }, "swifttla-evaluation-output-close"));
        try {
            tlc2.TLC.main(args);
        } finally {
            capture.close();
        }
    }

    @Override
    public synchronized void write(char[] value, int offset, int length) throws IOException {
        if (closed) {
            throw new IOException("TLC evaluation output is closed");
        }
        String text = new String(value, offset, length);
        byte[] encoded = text.getBytes(StandardCharsets.UTF_8);
        output.writeByte(1);
        output.writeInt(encoded.length);
        output.write(encoded);
        count++;
    }

    @Override
    public synchronized void flush() throws IOException {
        if (!closed) {
            output.flush();
        }
    }

    @Override
    public synchronized void close() throws IOException {
        if (closed) {
            return;
        }
        closed = true;
        output.writeByte(2);
        output.writeLong(count);
        output.close();
    }
}
