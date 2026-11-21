# Upstream Godzilla compatibility assets

The following files are copied **unchanged** from the Godzilla release used as
the protocol reference/ oracle:

- `asmx_shell.asmx.tpl` ← `shells/cryptions/cshapAes/template/shellAsmx.asmx`
- `asmx_request.xml.tpl` ← `shells/cryptions/cshapAes/template/asmxRequest.bin`
- `csharp_eval_shell.aspx.tpl` ← `shells/cryptions/cshapAes/template/evalShell.bin`
- `csharp_eval_loader.cs.tpl` ← `shells/cryptions/cshapAes/template/eval.bin`
- `asp_eval_shell.asp.tpl` ← `shells/cryptions/aspXor/template/AspEvalBase64.bin`
- `asp_eval_request.vbs.tpl` ← `shells/cryptions/aspXor/template/evalRequest.bin`
- `asp_eval_loader.asp.tpl` ← `shells/cryptions/aspXor/template/AspBase64.bin`

Reference artifact:

- `godzilla.jar`
- SHA-256: `62b7eff31d339fd04e6d39aba47b5f37b1b6feb27f85c3c71e4d2d600e8142c6`

Godzilla is distributed upstream under GPL. These files are kept as
compatibility fixtures so the Dart client can be checked byte-for-byte against
the original client. Do not redistribute this directory without confirming the
upstream license terms for the intended distribution.
