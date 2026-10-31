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

EMPTY :: NodeId(0)
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
    Block,
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
    op: TokenType,
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

Block :: struct {
    pos: u32,
    len: u32,
}

Module :: struct {
    nodes: []Node,
    lists: []NodeId,
    root: NodeId,
}

module_destroy :: proc(mod: ^Module) {
    delete(mod.nodes)
}

Parser :: struct {
    ts: ^TokenStream,
    nodes: [dynamic]Node,
    lists: [dynamic]NodeId,
}

peek :: proc(p: ^Parser) -> Token {
    return ts_peek(p.ts)
}

consume :: proc(p: ^Parser) {
    ts_consume(p.ts)
}

push_number :: proc(p: ^Parser, num: Number) -> NodeId {
    id := NodeId(len(p.nodes))
    append(&p.nodes, Leaf(num))
    return id
}

push_string :: proc(p: ^Parser, s: String) -> NodeId {
    id := NodeId(len(p.nodes))
    append(&p.nodes, Leaf(s))
    return id
}

push_node :: proc(p: ^Parser, n: Node) -> NodeId {
    id := NodeId(len(p.nodes))
    append(&p.nodes, n)
    return id
}

push_binary :: proc(p: ^Parser, op: TokenType, lhs: NodeId, rhs: NodeId) -> NodeId {
    id := NodeId(len(p.nodes))
    n: Node = BinaryOp {op, lhs, rhs}
    append(&p.nodes, n)
    return id
}

BINDING_POWER := #partial #sparse [TokenType][2]u8 {
    .Plus = {10, 11},
    .Minus = {10, 11},
    .Star = {20, 21},
    .Slash = {20, 21},
}

bp_lookup :: proc(ty: TokenType) -> (left_bp: u8, right_bp: u8, ok: bool) {
    bp := BINDING_POWER[ty]
    return bp[0], bp[1], bp[0] != 0
}

parse_expr :: proc(p: ^Parser, min_bp: u8 = 0) -> (node_id: NodeId, err: CompileError) {
    tok := peek(p)
    if tok.type == .End {
        err = ts_token_parse_error_create(
            p.ts,
            .Todo,
            "End of file when an expression was expected",
            "expected expression",
        )
        return
    }
    consume(p)
    fmt.eprintln(tok)

    lhs: NodeId
    #partial switch tok.type {
    case .LBracket:
        lhs = parse_expr(p) or_return
        if peek(p).type == .RBracket {
            consume(p)
        } else {
            err = ts_token_parse_error_create(
                p.ts,
                .Todo,
                "Unmatched `(` when parsing expression",
                "expected `)`",
            )
            return
        }
    case .Plus:
        fallthrough
    case .Minus:
        rhs := parse_expr(p, 25) or_return
        lhs = push_node(p, UnaryOp { tok, rhs })
    case .Number:
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
                    "Can only handle parsing integers",
                    "not an integer",
                )
                return
            }
        }
        lhs = push_number(p, whole)
    case .String:
        lhs = push_string(p, String {tok})
    case:
        err = ts_token_parse_error_create(
            p.ts,
            .Todo,
            fmt.tprintf("Token .%v invalid when parsing expression", tok.type),
            fmt.tprintf("invalid token .%v", tok.type),
        )
        return
    }

    for ;; {
        tok := peek(p)
        left_bp, right_bp, bp_ok := bp_lookup(tok.type)
        if !bp_ok || left_bp < min_bp {
            break
        }
        consume(p)

        rhs := parse_expr(p, right_bp) or_return
        lhs = push_binary(p, tok.type, lhs, rhs)
    }

    return lhs, nil
}

parse :: proc(ts: ^TokenStream) -> (module: Module, err: CompileError) {
    parser: Parser
    parser.ts = ts
    defer if err != nil {
        delete(parser.nodes)
    }

    p := &parser

    id := parse_block(p) or_return

    return {
        nodes = p.nodes[:],
        lists = p.lists[:],
        root = id,
    }, nil
}

parse_block :: proc(p: ^Parser) -> (node_id: NodeId, err: CompileError) {
    list_start := u32(len(p.lists))
    parse_loop: for ;; {
        tok := peek(p)
        #partial switch tok.type {
        case .Let:
            consume(p)

            tk := peek(p)
            if tk.type != .Ident {
                err = ts_token_parse_error_create(
                    p.ts,
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
                    p.ts,
                    .Todo,
                    "Expected `=` in variable declaration",
                    "expected `=` here",
                )
                return
            }
            consume(p)


            expr_node := parse_expr(p) or_return
            append(
                &p.nodes,
                p.nodes[decl_idx] = VariableDeclaration {
                    target = ident_tk,
                    expr = expr_node,
                },
            )

            append(&p.lists, len(p.nodes)-1)

        case .End:
            break parse_loop

        case:
            err = ts_token_parse_error_create(
                p.ts,
                .Todo,
                "TODO expressions/assignment",
            )
            return
        }
    }

    node_id = NodeId(len(p.nodes))
    append(
        &p.nodes,
        Block {
            pos = list_start,
            len = u32(len(p.lists)) - list_start,
        }
    )

    return
}
