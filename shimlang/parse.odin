package shimlang

import "core:fmt"

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

NodeId :: distinct i32

EMPTY :: NodeId(-1)
EMPTY_NODE :: Empty {}

Empty :: struct {}

Node :: union #no_nil {
    Empty,
    Leaf,
    UnaryOp,
    BinaryOp,
    Call,
    VariableDeclaration,
    Assignment,
}

Leaf :: union #no_nil {
    Ident,
    Number,
    String,
    Bool,
}

Ident :: struct {
    token: Token,
}

Number :: union #no_nil {
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

Module :: struct {
    nodes: []Node,
}

module_destroy :: proc(mod: ^Module) {
    delete(mod.nodes)
}

Parser :: struct {
    ts: ^TokenStream,
    nodes: [dynamic]Node,
}

peek :: proc(p: ^Parser) -> Token {
    return ts_peek(p.ts)
}

consume :: proc(p: ^Parser) {
    ts_consume(p.ts)
}

push_number :: proc(p: ^Parser, num: Number) -> NodeId{
    id := NodeId(len(p.nodes))
    append(&p.nodes, Leaf(num))
    return id
}

parse_expr :: proc(p: ^Parser) -> (node_id: NodeId, err: CompileError) {
    tok := peek(p)
    #partial switch tok.type {
    case .Number:
        consume(p)
        whole: i64 = 0
        for pos in tok.pos..<(tok.pos+tok.len) {
            b := p.ts.script[pos]
            whole *= 10
            if '0' <= b && b <= '9' {
                whole += i64(b - '0')
            } else {
                err = ts_token_parse_error_create(
                    p.ts,
                    .Todo,
                    "Can only handle parsingintegers",
                    "not an integer",
                )
                return
            }
        }
        node_id = push_number(p, whole)
        return
    }
    err = ts_token_parse_error_create(
        p.ts,
        .Todo,
        "Token invalid for parsing expression",
        "what do",
    )
    return
}

parse :: proc(ts: ^TokenStream) -> (module: Module, err: CompileError) {
    parser: Parser
    parser.ts = ts

    defer if err != nil {
        delete(parser.nodes)
    }

    p := &parser

    parse_loop: for ;; {
        tok := peek(p)
        #partial switch tok.type {
        case .Let:
            consume(p)

            tk := peek(p)
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
            consume(p)

            if peek(p).type != .Equal {
                err = ts_token_parse_error_create(
                    ts,
                    .Todo,
                    "Expected `=` in variable declaration",
                    "expected `=` here",
                )
                return
            }
            consume(p)

            decl_idx := len(p.nodes)
            append(&p.nodes, EMPTY_NODE)

            expr_node := parse_expr(p) or_return
            p.nodes[decl_idx] = VariableDeclaration {
                target = ident_tk,
                expr = expr_node,
            }

        case .End:
            break parse_loop

        case:
            err = ts_token_parse_error_create(
                ts,
                .Todo,
                "TODO expressions/assignment",
            )
            return
        }
    }

    return {
        nodes = p.nodes[:]
    }, nil
}
