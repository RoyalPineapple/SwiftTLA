package org.swifttla.conformance;

import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;

import tlc2.tool.TLCState;
import tlc2.value.impl.BoolValue;
import tlc2.value.impl.FcnRcdValue;
import tlc2.value.impl.IntValue;
import tlc2.value.impl.ModelValue;
import tlc2.value.impl.RecordValue;
import tlc2.value.impl.SetEnumValue;
import tlc2.value.impl.StringValue;
import tlc2.value.impl.TupleValue;
import tlc2.value.impl.Value;

/** Complete value identity for the versioned graph-evidence wire contract. */
final class CanonicalBinaryState {
    private static final byte[] VERSION = "STLASV01".getBytes(StandardCharsets.US_ASCII);
    private static final Comparator<byte[]> BYTES = Arrays::compareUnsigned;

    private CanonicalBinaryState() { }

    static byte[] encode(TLCState state) throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        DataOutputStream output = new DataOutputStream(bytes);
        output.write(VERSION);
        String[] names = state.getVarsAsStrings().clone();
        Arrays.sort(names, (left, right) -> BYTES.compare(utf8(left), utf8(right)));
        output.writeInt(names.length);
        for (String name : names) {
            string(output, name);
            Object binding = state.lookup(name);
            if (!(binding instanceof Value)) {
                throw new IOException("TLC state contains a non-Value binding: " + name);
            }
            output.write(value((Value) binding));
        }
        return bytes.toByteArray();
    }

    private static byte[] value(Value input) throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        DataOutputStream payload = new DataOutputStream(bytes);
        int tag;
        if (input instanceof IntValue) {
            tag = 1;
            payload.writeLong(((IntValue) input).val);
        } else if (input instanceof BoolValue) {
            tag = 2;
            payload.writeByte(((BoolValue) input).val ? 1 : 0);
        } else if (input instanceof StringValue) {
            tag = 3;
            payload.write(utf8(((StringValue) input).val.toString()));
        } else if (input instanceof ModelValue) {
            tag = 4;
            payload.write(utf8(((ModelValue) input).val.toString()));
        } else if (input instanceof TupleValue) {
            tag = 6;
            Value[] members = ((TupleValue) input).elems;
            payload.writeInt(members.length);
            for (Value member : members) { payload.write(value(member)); }
        } else if (input instanceof RecordValue) {
            RecordValue record = (RecordValue) input;
            if (record.names.length == 0) { return value(new TupleValue(new Value[0])); }
            String[] names = new String[record.names.length];
            for (int index = 0; index < names.length; index++) {
                names[index] = record.names[index].toString();
            }
            return record(names, record.values);
        } else if (input instanceof FcnRcdValue) {
            return function((FcnRcdValue) input);
        } else {
            Value function = input.toFcnRcd();
            if (function instanceof FcnRcdValue) { return value(function); }
            Value converted = input.toSetEnum();
            if (!(converted instanceof SetEnumValue)) {
                throw new IOException("unsupported TLC state value kind: " + input.getKindString());
            }
            tag = 5;
            SetEnumValue set = (SetEnumValue) converted;
            List<byte[]> members = new ArrayList<>(set.elems.size());
            for (int index = 0; index < set.elems.size(); index++) {
                members.add(value(set.elems.elementAt(index)));
            }
            members.sort(BYTES);
            int unique = 0;
            byte[] previous = null;
            for (byte[] member : members) {
                if (previous == null || !Arrays.equals(previous, member)) { unique++; }
                previous = member;
            }
            payload.writeInt(unique);
            previous = null;
            for (byte[] member : members) {
                if (previous == null || !Arrays.equals(previous, member)) { payload.write(member); }
                previous = member;
            }
        }
        return wrap(tag, bytes.toByteArray());
    }

    private static byte[] function(FcnRcdValue function) throws IOException {
        Value[] values = function.values;
        if (values.length == 0) { return value(new TupleValue(new Value[0])); }
        if (function.intv != null && function.intv.low == 1 && function.intv.high == values.length) {
            return value(new TupleValue(values));
        }
        Value[] keys = function.domain;
        if (keys == null) {
            keys = new Value[values.length];
            for (int index = 0; index < values.length; index++) {
                keys[index] = IntValue.gen(function.intv.low + index);
            }
        }
        Value[] indexed = new Value[values.length];
        boolean tuple = true;
        boolean record = true;
        String[] names = new String[values.length];
        for (int index = 0; index < keys.length; index++) {
            if (keys[index] instanceof IntValue) {
                int ordinal = ((IntValue) keys[index]).val;
                if (ordinal < 1 || ordinal > values.length || indexed[ordinal - 1] != null) {
                    tuple = false;
                } else {
                    indexed[ordinal - 1] = values[index];
                }
            } else {
                tuple = false;
            }
            if (keys[index] instanceof StringValue) {
                names[index] = ((StringValue) keys[index]).val.toString();
            } else {
                record = false;
            }
        }
        if (tuple) { return value(new TupleValue(indexed)); }
        if (record) { return record(names, values); }
        List<byte[][]> entries = new ArrayList<>(keys.length);
        for (int index = 0; index < keys.length; index++) {
            entries.add(new byte[][] {value(keys[index]), value(values[index])});
        }
        entries.sort((left, right) -> BYTES.compare(left[0], right[0]));
        for (int index = 1; index < entries.size(); index++) {
            if (Arrays.equals(entries.get(index - 1)[0], entries.get(index)[0])) {
                throw new IOException("duplicate canonical function key");
            }
        }
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        DataOutputStream output = new DataOutputStream(bytes);
        output.writeInt(entries.size());
        for (byte[][] entry : entries) {
            output.write(entry[0]);
            output.write(entry[1]);
        }
        return wrap(8, bytes.toByteArray());
    }

    private static byte[] record(String[] names, Value[] values) throws IOException {
        Integer[] order = new Integer[names.length];
        for (int index = 0; index < order.length; index++) { order[index] = index; }
        Arrays.sort(order, (left, right) -> BYTES.compare(utf8(names[left]), utf8(names[right])));
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        DataOutputStream output = new DataOutputStream(bytes);
        output.writeInt(order.length);
        for (int index : order) {
            string(output, names[index]);
            output.write(value(values[index]));
        }
        return wrap(7, bytes.toByteArray());
    }

    private static byte[] wrap(int tag, byte[] payload) throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream(payload.length + 5);
        DataOutputStream output = new DataOutputStream(bytes);
        output.writeByte(tag);
        output.writeInt(payload.length);
        output.write(payload);
        return bytes.toByteArray();
    }

    private static void string(DataOutputStream output, String value) throws IOException {
        byte[] bytes = utf8(value);
        output.writeInt(bytes.length);
        output.write(bytes);
    }

    private static byte[] utf8(String value) {
        return value.getBytes(StandardCharsets.UTF_8);
    }
}
