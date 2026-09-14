package org.swifttla.conformance;

import java.io.StringReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.List;
import java.util.Map;
import java.util.stream.IntStream;

import com.google.gson.Gson;
import tla2sany.parser.SimpleCharStream;
import tla2sany.parser.TLAplusParserConstants;
import tla2sany.parser.TLAplusParserTokenManager;
import tlc2.tool.impl.ModelConfig;
import tlc2.util.Vect;

/** Parses the model definition and check declarations once for validation. */
public final class ConfigurationParser {
    private ConfigurationParser() {}

    public static void main(String[] arguments) throws Exception {
        if (arguments.length != 2) {
            throw new IllegalArgumentException("Expected input.cfg output.json");
        }
        Path input = Path.of(arguments[0]);
        String source = Files.readString(input, StandardCharsets.UTF_8);
        // ModelConfig catches lexer errors as EOF. Validate with its own lexer first.
        var lexer = new TLAplusParserTokenManager(new SimpleCharStream(new StringReader(source), 1, 1), 2);
        while (lexer.getNextToken().kind != TLAplusParserConstants.EOF) {}
        var configuration = new ModelConfig(input.toString(), null);
        configuration.parse();
        String result = new Gson().toJson(Map.of(
            "declarations", declarations(configuration),
            "invariants", strings(configuration.getInvariants()),
            "properties", strings(configuration.getProperties()),
            "checksDeadlock", configuration.getCheckDeadlock()
        ));
        Files.writeString(Path.of(arguments[1]), result + "\n", StandardCharsets.UTF_8,
            StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE);
    }

    static String declarations(ModelConfig original) {
        StringBuilder result = new StringBuilder();
        for (String constants : original.getRawConstants()) {
            result.append(constants).append('\n');
        }
        append(result, "INIT", original.getInit());
        append(result, "NEXT", original.getNext());
        append(result, "SPECIFICATION", original.getSpec());
        append(result, "CONSTRAINT", strings(original.getConstraints()));
        append(result, "ACTION_CONSTRAINT", strings(original.getActionConstraints()));
        append(result, "VIEW", original.getView());
        append(result, "ALIAS", original.getAlias());
        append(result, "POSTCONDITION", strings(original.getPostConditions()));
        append(result, "_PERIODIC", original.getPeriodic());
        append(result, "_RL_REWARD", original.getRLReward());
        append(result, "_POSSIBLE", strings(original.getPossible()));
        return result.toString();
    }

    private static List<String> strings(Vect<?> values) {
        return IntStream.range(0, values.size()).mapToObj(index -> (String) values.elementAt(index)).toList();
    }

    private static void append(StringBuilder output, String keyword, Iterable<String> values) {
        for (String value : values) { append(output, keyword, value); }
    }

    private static void append(StringBuilder output, String keyword, String value) {
        if (!value.isEmpty()) { output.append(keyword).append(' ').append(value).append('\n'); }
    }
}
