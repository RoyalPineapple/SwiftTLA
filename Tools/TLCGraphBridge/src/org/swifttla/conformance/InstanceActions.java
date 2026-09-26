package org.swifttla.conformance;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.IdentityHashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import tla2sany.semantic.APSubstInNode;
import tla2sany.semantic.ExprOrOpArgNode;
import tla2sany.semantic.FormalParamNode;
import tla2sany.semantic.LabelNode;
import tla2sany.semantic.LetInNode;
import tla2sany.semantic.OpApplNode;
import tla2sany.semantic.OpDefNode;
import tla2sany.semantic.SemanticNode;
import tla2sany.semantic.Subst;
import tla2sany.semantic.SubstInNode;
import tlc2.tool.Action;
import tlc2.tool.BuiltInOPs;
import tlc2.tool.EvalControl;
import tlc2.tool.IContextEnumerator;
import tlc2.tool.ITool;
import tlc2.tool.TLCState;
import tlc2.tool.ToolGlobals;
import tlc2.util.Context;

/** Refines TLC's substituted action using only the pinned reference semantics. */
final class InstanceActions implements ToolGlobals {
    private final Map<Action, List<Action>> decompositions = new IdentityHashMap<>();

    List<Action> matching(ITool tool, Action original, TLCState source, TLCState target) {
        if (original == null) {
            throw new IllegalArgumentException("Transition has no Action identity");
        }
        if (!(original.pred instanceof SubstInNode) && !(original.pred instanceof APSubstInNode)) {
            if (!original.isNamed() && original.pred instanceof OpApplNode call
                    && call.getArgs().length == 0 && call.getOperator() instanceof OpDefNode definition
                    && definition.getArity() == 0) {
                return List.of(new Action(original.pred, original.con, definition));
            }
            return List.of(original);
        }
        if (tool == null) {
            throw new IllegalStateException("INSTANCE resolution requires the active TLC checker");
        }
        List<Action> leaves = decompositions.computeIfAbsent(original, action -> {
            var result = new ArrayList<Action>();
            split(tool, action.pred, action.con, action.getOpDef(), new HashSet<>(), result);
            return List.copyOf(result);
        });
        var matches = new LinkedHashMap<String, Action>();
        for (Action leaf : leaves) {
            if (tool.isValid(leaf, source, target)) {
                matches.putIfAbsent(leaf.getInvocationSignature(), leaf);
            }
        }
        if (matches.isEmpty()) {
            throw new IllegalStateException("No substituted leaf action admits the TLC transition");
        }
        return List.copyOf(matches.values());
    }

    private void split(ITool tool, SemanticNode node, Context context, OpDefNode owner,
                       Set<SemanticNode> active, List<Action> result) {
        if (!active.add(node)) {
            throw new IllegalArgumentException("Recursive action decomposition at " + node.getLocation());
        }
        try {
            if (node instanceof SubstInNode substitution) {
                requireUnqualified(owner);
                split(tool, substitution.getBody(), substitute(tool, substitution.getSubsts(), context), owner, active, result);
            } else if (node instanceof APSubstInNode substitution) {
                requireUnqualified(owner);
                split(tool, substitution.getBody(), substitute(tool, substitution.getSubsts(), context), owner, active, result);
            } else if (node instanceof LetInNode binding) {
                split(tool, binding.getBody(), context, owner, active, result);
            } else if (node instanceof LabelNode label) {
                split(tool, label.getBody(), context, owner, active, result);
            } else if (node instanceof OpApplNode call) {
                int opcode = BuiltInOPs.getOpCode(call.getOperator().getName());
                if (opcode == 0) {
                    Object resolved = tool.lookup(call.getOperator(), context, false);
                    if (resolved instanceof OpDefNode definition
                            && BuiltInOPs.getOpCode(definition.getName()) == 0) {
                        FormalParamNode[] parameters = definition.getParams();
                        ExprOrOpArgNode[] arguments = call.getArgs();
                        if (parameters.length != arguments.length) {
                            throw new IllegalArgumentException("Action argument count changed during substitution");
                        }
                        Context bound = context;
                        for (int index = 0; index < arguments.length; index++) {
                            if (arguments[index].getLevel() != 0) {
                                throw new IllegalArgumentException("State-dependent action arguments need explicit identity support");
                            }
                            bound = bound.cons(parameters[index], tool.eval(arguments[index], context, TLCState.Empty));
                        }
                        split(tool, definition.getBody(), bound, definition, active, result);
                        return;
                    }
                }
                if (opcode == OPCODE_dl || opcode == OPCODE_lor) {
                    for (ExprOrOpArgNode argument : call.getArgs()) {
                        split(tool, argument, context, owner, active, result);
                    }
                } else if (opcode == OPCODE_be) {
                    IContextEnumerator bindings = tool.contexts(call, context, TLCState.Empty, TLCState.Empty, EvalControl.Clear);
                    Context bound;
                    while ((bound = bindings.nextElement()) != null) {
                        split(tool, call.getArgs()[0], bound, owner, active, result);
                    }
                } else {
                    Action leaf = new Action(node, context, owner);
                    if (!leaf.isNamed() || leaf.getParameters().size() != owner.getArity()) {
                        throw new IllegalArgumentException("Substituted action lacks a complete named invocation");
                    }
                    result.add(leaf);
                }
            } else {
                throw new IllegalArgumentException("Unsupported action prefix at " + node.getLocation());
            }
        } finally {
            active.remove(node);
        }
    }

    private Context substitute(ITool tool, Subst[] substitutions, Context original) {
        Context result = original;
        for (Subst substitution : substitutions) {
            result = result.cons(substitution.getOp(), tool.getVal(substitution.getExpr(), original, false));
        }
        return result;
    }

    private void requireUnqualified(OpDefNode owner) {
        if (owner != null && owner.getName().toString().contains("!")) {
            throw new IllegalArgumentException("Named INSTANCE namespaces require qualified action identity support");
        }
    }
}
