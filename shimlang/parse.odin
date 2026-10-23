package shimlang

import "core:fmt"

Module :: struct{
}

// We want to be able to run code at the top level of a file, but we also want
// to be able to call functions mutually-recursively. We can't impose a strict
// ordering on `fn A` needing to be declared before `fn B` if they call each
// other. Likewise, a function might read a global variable and we'd want to
// (at some point) validate that the variable is initialized before it's called.
//
// Ignoring that validation pass, it should be equivalent to have all the
// fn/struct declarations followed by the rest of the script. Shadowing does add
// some complications for which global variable is captured/referenced by a
// declaration.

NodeId :: distinct int;

Node :: union {
    Leaf,
    UnaryOp,
    BinaryOp,
    Call,
    VariableDeclaration,
    Assignment,
}

Leaf :: union {
    Ident,
    Number,
    String,
    Bool,
}

Ident :: struct {
    token: Token,
}

Number :: union {
    i64,
    f64,
}

String :: struct {
    token: Token,
}

Bool :: enum {
    True,
    False,
}

UnaryOp :: struct {
    op: Token,
    child: NodeId,
}

BinaryOp :: struct {
    op: Token,
    left: NodeId,
    right: NodeId,
}

Call :: struct {
    callable: NodeId,
    arg_count: int,
    arg_start: NodeId,
}

VariableDeclaration :: struct {
    target: Token,
    expr: NodeId,
}

Assignment :: struct {
    target: Token,
    expr: NodeId,
}

parse :: proc(ts: ^TokenStream) -> (module: Module, err: CompileError) {
    for ;; {
        tok := ts_peek(ts)
        #partial switch tok.type {
        case .Let:
            ts_consume(ts)

            tk := ts_peek(ts)
            if tk.type != .Ident {
                err = ts_token_parse_error_create(
                    ts,
                    .VariableDeclarationNotIdent,
                    "VariableDeclarationNotIdent",
                    "this should be an identifier",
                )
                return
            }
            ident_tk := tk
            ts_consume(ts)

            if ts_peek(ts).type != .Equal {
                err = ts_token_parse_error_create(
                    ts,
                    .Todo,
                    "Expected `=` in variable declaration",
                    "expected `=` here",
                )
                return
            }
            ts_consume(ts)

            err = ts_token_parse_error_create(
                ts,
                .Todo,
                "TODO: Parse the expression",
                "expression parsing not implemented",
            )
            return

        case:
            fmt.println("TODO expressions/assignment")
                err = ts_token_parse_error_create(
                    ts,
                    .Todo,
                    "TODO expressions/assignment",
                )
            return
        }
    }

    return {}, nil
}
