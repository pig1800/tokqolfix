// Seed a raw 6502 program with candidate routine entries, run auto-analysis,
// and export functions, instructions, call edges and decompiled C.
// @category REA
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.decompiler.DecompileOptions;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionManager;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.listing.Program;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

public class SeedExport extends GhidraScript {
    private static String esc(String s) {
        if (s == null) return "null";
        StringBuilder b = new StringBuilder("\"");
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"': b.append("\\\""); break;
                case '\\': b.append("\\\\"); break;
                case '\n': b.append("\\n"); break;
                case '\r': b.append("\\r"); break;
                case '\t': b.append("\\t"); break;
                default:
                    if (c < 0x20) b.append(String.format("\\u%04x", (int) c));
                    else b.append(c);
            }
        }
        return b.append('"').toString();
    }

    private void writeJson(Program program, Path out) throws Exception {
        FunctionManager fm = program.getFunctionManager();
        Listing listing = program.getListing();
        DecompInterface decomp = new DecompInterface();
        DecompileOptions opts = new DecompileOptions();
        decomp.setOptions(opts);
        decomp.toggleCCode(true);
        decomp.toggleSyntaxTree(true);
        decomp.openProgram(program);

        List<Function> funcs = new ArrayList<>();
        for (Function f : fm.getFunctions(true)) {
            if (f.isExternal()) continue;
            funcs.add(f);
        }
        funcs.sort((a, b) -> a.getEntryPoint().compareTo(b.getEntryPoint()));

        try (PrintWriter w = new PrintWriter(Files.newBufferedWriter(out))) {
            w.println("{");
            w.println("  \"program\": " + esc(program.getName()) + ",");
            w.println("  \"image_base\": " + esc(program.getImageBase().toString()) + ",");
            w.println("  \"functions\": [");
            for (int fi = 0; fi < funcs.size(); fi++) {
                Function f = funcs.get(fi);
                if (fi > 0) w.println(",");
                w.println("    {");
                w.println("      \"name\": " + esc(f.getName()) + ",");
                w.println("      \"entry\": " + esc(f.getEntryPoint().toString()) + ",");
                w.println("      \"body\": " + esc(f.getBody().toString()) + ",");
                w.println("      \"size\": " + f.getBody().getNumAddresses() + ",");
                w.println("      \"calling\": [");
                int ci = 0;
                for (Function c : f.getCallingFunctions(monitor)) {
                    if (ci++ > 0) w.println(",");
                    w.print("        " + esc(c.getEntryPoint().toString()));
                }
                w.println("\n      ],");
                w.println("      \"called\": [");
                ci = 0;
                for (Function c : f.getCalledFunctions(monitor)) {
                    if (ci++ > 0) w.println(",");
                    w.print("        " + esc(c.getEntryPoint().toString()));
                }
                w.println("\n      ],");
                w.println("      \"instructions\": [");
                InstructionIterator it = listing.getInstructions(f.getBody(), true);
                int ii = 0;
                while (it.hasNext()) {
                    Instruction ins = it.next();
                    if (ii++ > 0) w.println(",");
                    String mnemonic = ins.getMnemonicString();
                    String ops = "";
                    int nops = ins.getNumOperands();
                    for (int oi = 0; oi < nops; oi++) {
                        if (oi > 0) ops += ",";
                        ops += ins.getDefaultOperandRepresentation(oi);
                    }
                    w.print("        {\"addr\":" + esc(ins.getAddress().toString())
                            + ",\"mnemonic\":" + esc(mnemonic)
                            + ",\"operands\":" + esc(ops)
                            + ",\"text\":" + esc(ins.toString()) + "}");
                }
                w.println("\n      ],");
                String ctext = "";
                try {
                    DecompileResults dr = decomp.decompileFunction(f, 60, monitor);
                    if (dr != null && dr.decompileCompleted() && dr.getDecompiledFunction() != null) {
                        ctext = dr.getDecompiledFunction().getC();
                    }
                } catch (Exception e) {
                    ctext = "/* decompile error: " + e.getMessage() + " */";
                }
                w.println("      \"c\": " + esc(ctext));
                w.println("    }");
            }
            w.println("  ]");
            w.println("}");
        }
        decomp.dispose();
    }

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) {
            println("usage: SeedExport.java <entries.txt> <out.json>");
            return;
        }
        Path entries = Path.of(args[0]);
        Path out = Path.of(args[1]);
        Program program = currentProgram;
        Address base = program.getImageBase();
        if (Files.exists(entries)) {
            for (String line : Files.readAllLines(entries)) {
                line = line.trim();
                if (line.isEmpty() || line.startsWith("#")) continue;
                if (line.startsWith("0x")) line = line.substring(2);
                Address a = program.getAddressFactory().getDefaultAddressSpace().getAddress(line);
                if (a == null) continue;
                if (getFunctionAt(a) != null) continue;
                try {
                    disassemble(a);
                    createFunction(a, null);
                } catch (Exception e) {
                    println("seed failed at " + a + ": " + e.getMessage());
                }
            }
        }
        println("seeded functions, running analysis...");
        analyzeAll(program);
        println("analysis complete, exporting...");
        writeJson(program, out);
        println("wrote " + out);
    }
}
