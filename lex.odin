package lex

import "core:fmt"
import "core:os"
import "core:mem"

// Jai uses the literal character as the value of single-letter tokens, which
// seems more reasonable than having it be arbitrary
TokenType :: enum(u8) {
    End = 0,
    Number,
    Ident,
    String,
    DoubleEqual,
    BangEqual,
    PlusEqual,
    MinusEqual,
    StarEqual,
    SlashEqual,
    PercentEqual,
    LAngleEqual,
    RAngleEqual,
    Let,
    Fn,
    If,
    Else,
    For,
    While,
    Return,
    Struct,
    True,
    False,
    Break,
    Continue,
    Bang = '!',
    Plus = '+',
    Minus = '-',
    Star = '*',
    Slash = '/',
    Percent = '%',
    LBracket = '(',
    RBracket = ')',
    LCurly = '{',
    RCurly = '}',
    LAngle = '<',
    RAngle = '>',
    LSquare = '[',
    RSquare = ']',
    Colon = ':',
    SemiColon = ';',
    Comma = ',',
    Dot = '.',
    Equal = '=',
}

Token :: struct {
    type: TokenType,
    pos: u32,
    len: u32,
}

CompileError :: union {
    os.Error,
    LexError,
}

LexError :: enum {
    InvalidTokenStart,
    IncompleteMultilineComment,
    IncompleteString,
    NonAsciiData,
}

human_row_col :: proc(data: []byte, idx: u32) -> (row: u32, col: u32) {
    col = 1
    row = 1
    for b, i in data {
        if u32(i) == idx {
            break
        }

        col += 1
        if b == '\n' {
            row += 1
            col = 1
        }
    }
    return
}

read_entire_file_with_padding_from_path :: proc(name: string, padding: uint) -> (data: []byte, err: os.Error) {
    f, ferr := os.open(name)
    if ferr != nil {
        return nil, ferr
    }
    defer os.close(f)

    size, serr := os.file_size(f)
    if serr != nil {
        return nil, serr
    }

    bytes := make([dynamic]u8, uint(size)+padding)

    n, nerr := os.read_full(f, bytes[:size])
    if nerr != nil {
        return nil, nerr
    }

    return bytes[:], nil
}


TokenStream :: struct {
    script: []byte,
    tokens: []Token,
}

token_stream_destroy :: proc(ts: ^TokenStream, allocator := context.allocator) {
    delete(ts.script)
    delete(ts.tokens)
    ts^ = {}
}

ident_to_token_type :: proc(s: string) -> TokenType {
    switch s {
    case "if":
        return .If
    case "else":
        return .Else
    case "while":
        return .While
    case "for":
        return .For
    case "fn":
        return .Fn
    case "return":
        return .Return
    case "struct":
        return .Struct
    case "true":
        return .True
    case "false":
        return .False
    case "break":
        return .Break
    case "continue":
        return .Continue
    case "let":
        return .Let
    }
    return .Ident
}


lex :: proc() -> (ts: TokenStream, err: CompileError) {
    // Read the text and pad the end with 0's to avoid needing bounds checks
    // (just need a few extra bytes now, but SIMD may need more)
    data := read_entire_file_with_padding_from_path("game.shm", padding = 16) or_return
    defer if err != nil {
        delete(data)
    }

    // Check for ASCII
    for b, i in data {
        if b >= 127 {
            fmt.println("Hit invalid byte at index", i)
            err = .NonAsciiData
            return
        }
    }

    output: [dynamic]Token
    defer if err != nil {
        delete(output)
    }

    // Moving to SIMD could help us go from ~13 ns/token to ~8 ns/token based
    // on other parsers, but this is unlikely to be much of a bottleneck
    // compared to parsing and type checking

    for i := u32(0); data[i] != 0; i += 1 {
        b := data[i]
        // The byte is checked with the most common bytes/tokens tested earlier
        if b == ' ' || b == '\n' || data[i] == '\t' || data[i] == '\r' {
            i += 1
            // Skip whitespace in a tight loop, since this helps a lot for leading
            // whitespace in a line
            for ; data[i] == ' ' || data[i] == '\n' || data[i] == '\t' || data[i] == '\r'; i += 1 {}
            i -= 1
            // TODO: Will need to handle newline-delimited statements
        } else if ('A' <= b && b <= 'Z') || ('a' <= b && b <='z') || b == '_' {
            pos := i
            for ; ; i += 1 {
                b = data[i]
                if !('A' <= b && b <= 'Z') && !('a' <= b && b <='z') && !('0' <= b && b <= '9') && b != '_' {
                    i -= 1
                    break
                }
            }
            append(&output, {ident_to_token_type(string(data[pos:i+1])), pos, i-pos+1})
        } else if b == ',' {
            append(&output, {.Comma, i, 1})
        } else if b == '=' {
            if data[i+1] == '=' {
                append(&output, {.DoubleEqual, i, 2})
                i += 1
            } else {
                append(&output, {.Equal, i, 1})
            }
        } else if b == '(' {
            append(&output, {.LBracket, i, 1})
        } else if b == ')' {
            append(&output, {.RBracket, i, 1})
        } else if b == '.' {
            append(&output, {.Dot, i, 1})
        } else if b == '{' {
            append(&output, {.LCurly, i, 1})
        } else if b == '}' {
            append(&output, {.RCurly, i, 1})
        } else if b == '[' {
            append(&output, {.LSquare, i, 1})
        } else if b == ']' {
            append(&output, {.RSquare, i, 1})
        } else if '0' <= b && b <= '9' {
            pos := i
            for ;; i += 1 {
                b = data[i]
                if !('0' <= b && b <= '9') && b != '.' && b != 'e' && b != 'E' {
                    i -= 1
                    break
                }
            }
            append(&output, {.Number, pos, i-pos+1})
        } else if b == '+' {
            if data[i+1] == '=' {
                append(&output, {.PlusEqual, i, 2})
                i += 1
            } else {
                append(&output, {.Plus, i, 1})
            }
        } else if b == '*' {
            if data[i+1] == '=' {
                append(&output, {.StarEqual, i, 2})
                i += 1
            } else {
                append(&output, {.Star, i, 1})
            }
        } else if b == '-' {
            if data[i+1] == '=' {
                append(&output, {.MinusEqual, i, 2})
                i += 1
            } else {
                append(&output, {.Minus, i, 1})
            }
        } else if b == ':' {
            append(&output, {.Colon, i, 1})
        } else if b == ';' {
            append(&output, {.SemiColon, i, 1})
        } else if b == '"' {
            pos := i
            i += 1
            for ; data[i] != 0 ; i += 1 {
                // TODO: String interpolation
                if data[i] == '"' {
                    break
                }
            }
            if data[i] == 0 {
                err = .IncompleteString
                return
            }
            append(&output, {.String, pos, i-pos+1})
        } else if b == '!' {
            if data[i+1] == '=' {
                append(&output, {.BangEqual, i, 2})
                i += 1
            } else {
                append(&output, {.Bang, i, 1})
            }
        } else if b == '<' {
            if data[i+1] == '=' {
                append(&output, {.LAngleEqual, i, 2})
                i += 1
            } else {
                append(&output, {.LAngle, i, 1})
            }
        } else if b == '>' {
            if data[i+1] == '=' {
                append(&output, {.RAngleEqual, i, 2})
                i += 1
            } else {
                append(&output, {.RAngle, i, 1})
            }
        } else if b == '/' {
            if data[i+1] == '=' {
                append(&output, {.SlashEqual, i, 2})
                i += 1
            } else if data[i+1] == '/' {
                // This is a comment, skip the rest of the line
                for ; data[i+1] != '\n' && data[i+1] != 0 ; i += 1 {}
            } else if data[i+1] == '*' {
                i += 2
                nesting := 1
                // This is a multiline comment
                for ; data[i] != 0; i += 1 {
                    if data[i] == '/' && data[i+1] == '*' {
                        nesting += 1
                        i += 1
                    }
                    else if data[i] == '*' && data[i+1] == '/' {
                        nesting -= 1
                        i += 1
                    }
                    if nesting == 0 {
                        break
                    }
                }
                if nesting != 0 {
                    err = .IncompleteMultilineComment
                    return
                }
            } else {
                append(&output, {.Slash, i, 1})
            }
        } else if b == '%' {
            if data[i+1] == '=' {
                append(&output, {.PercentEqual, i, 2})
                i += 1
            } else {
                append(&output, {.Percent, i, 1})
            }
        } else {
            // TODO: Construct a proper error
            row, col := human_row_col(data, i)
            fmt.printfln("Token error (%v,%v)", row, col)
            err = .InvalidTokenStart
            return
        }
    }

    ts = {
        script = data,
        tokens = output[:],
    }
    return
}

print_tokens :: proc(ts: TokenStream) {
    for token in ts.tokens {
        switch token.type {
        case .Ident:
            fmt.printfln("`%s`", ts.script[token.pos:token.pos+token.len])
        case .String:
            fmt.printfln("%s", ts.script[token.pos:token.pos+token.len])
        case .End:
            fmt.println("END")
        case .Let:
            fmt.println("let")
        case .If:
            fmt.println("if")
        case .Else:
            fmt.println("else")
        case .While:
            fmt.println("while")
        case .For:
            fmt.println("for")
        case .Fn:
            fmt.println("fn")
        case .Return:
            fmt.println("return")
        case .Struct:
            fmt.println("struct")
        case .True:
            fmt.println("true")
        case .False:
            fmt.println("false")
        case .Break:
            fmt.println("break")
        case .Continue:
            fmt.println("continue")
        case .Number:
            fmt.printfln("#%s", ts.script[token.pos:token.pos+token.len])
        case .Bang:
            fmt.println("!")
        case .Plus:
            fmt.println("+")
        case .Minus:
            fmt.println("-")
        case .Star:
            fmt.println("*")
        case .Slash:
            fmt.println("/")
        case .Percent:
            fmt.println("%")
        case .LBracket:
            fmt.println("(")
        case .RBracket:
            fmt.println(")")
        case .LCurly:
            fmt.println("{")
        case .RCurly:
            fmt.println("}")
        case .LAngle:
            fmt.println("<")
        case .RAngle:
            fmt.println(">")
        case .LSquare:
            fmt.println("[")
        case .RSquare:
            fmt.println("]")
        case .Colon:
            fmt.println(":")
        case .SemiColon:
            fmt.println(";")
        case .Comma:
            fmt.println(",")
        case .Dot:
            fmt.println(".")
        case .Equal:
            fmt.println("=")
        case .BangEqual:
            fallthrough
        case .PlusEqual:
            fallthrough
        case .MinusEqual:
            fallthrough
        case .StarEqual:
            fallthrough
        case .SlashEqual:
            fallthrough
        case .PercentEqual:
            fallthrough
        case .DoubleEqual:
            fallthrough
        case .LAngleEqual:
            fallthrough
        case .RAngleEqual:
            fmt.println(token.type)
        }
    }
}

run :: proc() -> (res: bool, err: CompileError) {
    ts := lex() or_return
    defer token_stream_destroy(&ts)
    fmt.println(len(ts.tokens))

    //print_tokens(ts)

    res = true
    return
}

main :: proc() {
    when ODIN_DEBUG {
        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        context.allocator = mem.tracking_allocator(&track)

        defer {
            if len(track.allocation_map) > 0 {
                fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
                for _, entry in track.allocation_map {
                    fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
                }
            }
            mem.tracking_allocator_destroy(&track)
        }
    }

    res, err := run()
    if err != nil {
        fmt.println("hit some error")
        fmt.println(err)
    }
}
