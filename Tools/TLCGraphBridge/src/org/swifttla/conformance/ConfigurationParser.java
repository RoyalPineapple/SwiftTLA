package org.swifttla.conformance;

import java.io.StringReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;
import java.util.List;
import java.util.Map;
import java.util.stream.IntStream;

import com.google.gson.Gson;
import tla2sany.drivers.SANY;
import tla2sany.drivers.SanyExitCode;
import tla2sany.drivers.SanySettings;
import tla2sany.modanalyzer.SpecObj;
import tla2sany.output.LogLevel;
import tla2sany.output.SimpleSanyOutput;
import tla2sany.semantic.ModuleNode;
import tla2sany.semantic.OpApplNode;
import tla2sany.semantic.OpDefNode;
import tla2sany.parser.SimpleCharStream;
import tla2sany.parser.TLAplusParserConstants;
import tla2sany.parser.TLAplusParserTokenManager;
import tlc2.tool.impl.ModelConfig;
import tlc2.util.Vect;

/** Parses the model definition and check declarations once for validation. */
public final class ConfigurationParser {
    private ConfigurationParser() {}

    public static void main(String[] arguments) throws Exception {
        if (arguments.length < 3) {
            throw new IllegalArgumentException("Expected module.tla input.cfg output.json [native check names ...]");
        }
        Path input = Path.of(arguments[1]);
        String source = Files.readString(input, StandardCharsets.UTF_8);
        // ModelConfig catches lexer errors as EOF. Validate with its own lexer first.
        var lexer = new TLAplusParserTokenManager(new SimpleCharStream(new StringReader(source), 1, 1), 2);
        while (lexer.getNextToken().kind != TLAplusParserConstants.EOF) {}
        var configuration = new ModelConfig(input.toString(), null);
        configuration.parse();
        Set<String> nativeChecks = Set.of(Arrays.copyOfRange(arguments, 3, arguments.length));
        List<String> invariants = strings(configuration.getInvariants());
        List<String> properties = strings(configuration.getProperties());
        if (!nativeChecks.containsAll(invariants) || !nativeChecks.containsAll(properties)) {
            var spec = new SpecObj(arguments[0], null);
            var status = SANY.parse(spec, arguments[0],
                new SimpleSanyOutput(System.err, LogLevel.ERROR), SanySettings.validAstSettings());
            if (status != SanyExitCode.OK || spec.getErrorLevel() != 0
                || !spec.getParseErrors().isSuccess() || !spec.getSemanticErrors().isSuccess()) {
                throw new IllegalArgumentException("Cannot resolve checks in an invalid TLA+ module");
            }
            ModuleNode module = spec.getRootModule();
            invariants = invariants.stream().map(name -> resolve(name, module, configuration, nativeChecks)).distinct().toList();
            properties = properties.stream().map(name -> resolve(name, module, configuration, nativeChecks)).distinct().toList();
        }
        String result = new Gson().toJson(Map.of(
            "declarations", declarations(configuration),
            "invariants", invariants,
            "properties", properties,
            "checksDeadlock", configuration.getCheckDeadlock()
        ));
        Files.writeString(Path.of(arguments[2]), result + "\n", StandardCharsets.UTF_8,
            StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE);
    }

    private static String resolve(String name, ModuleNode module, ModelConfig configuration, Set<String> nativeChecks) {
        // Module-scoped replacements need substitution-aware resolution; retain the
        // original name so unsupported coverage fails rather than changing a check.
        if (!configuration.getModOverrides().isEmpty()) { return name; }
        OpDefNode definition = module.getOpDef(name);
        Set<OpDefNode> visited = new HashSet<>();
        while (definition != null && !nativeChecks.contains(name)) {
            if (configuration.getOverrides().containsKey(name)) { break; }
            if (!visited.add(definition)) { throw new IllegalArgumentException("Cyclic check alias: " + name); }
            if (!(definition.getBody() instanceof OpApplNode call) || call.getArgs().length != 0
                || !(call.getOperator() instanceof OpDefNode target)) { break; }
            definition = target;
            name = target.getName().toString();
        }
        return name;
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
