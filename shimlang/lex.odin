package shimlang

import "core:fmt"
import "core:os"
import "core:mem"
import "core:bytes"
import "core:strings"

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
    newline: bool,
    pos: u32,
    len: u32,
}

CompileError :: union {
    os.Error,
    LexError,
    ParseError,
}

LexError :: struct {
    type: LexErrorType,
    info: ErrorInfo,
}

LexErrorType :: enum {
    InvalidTokenStart,
    IncompleteMultilineComment,
    IncompleteString,
    NonAsciiData,
}

ParseError :: struct {
    type: ParseErrorType,
    info: ErrorInfo,
}

ParseErrorType :: enum {
    VariableDeclarationNotIdent,
    Todo,
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

byte_from_row_col :: proc(data: []byte, row: u32, col: u32) -> u32 {
    if row == 1 && col == 1 {
        return 0
    }
    tcol := u32(1)
    trow := u32(1)
    for b, i in data {
        tcol += 1
        if b == '\n' {
            trow += 1
            tcol = 1
        }

        if trow == row && tcol >= col || trow > row {
            // +1 since we want to return the character _after_ the newline
            return u32(i+1)
        }
    }
    return u32(len(data)-1)
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
    idx: int,
}

token_stream_destroy :: proc(ts: ^TokenStream, allocator := context.allocator) {
    delete(ts.script)
    delete(ts.tokens)
    ts^ = {}
}

ts_peek :: proc(ts: ^TokenStream) -> Token {
    return ts.tokens[ts.idx]
}

ts_consume :: proc(ts: ^TokenStream) {
    when ODIN_DEBUG {
        // ts.idx should always be a valid index
        // We pad the tokens with multiple `END` tokens to avoid needing to check
        // if we've run out of tokens (outside of normal bounds checking).
        // A correctly-implemented parser shouldn't be consuming the END tokens
        assert(ts.idx < len(ts.tokens) - 1)
        assert(ts.tokens[ts.idx].type != .End)
    }
    ts.idx += 1
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

/*

Store the information needed to print errors like:


Error: Got 13 arguments, but only used 2
    --> game.shm(18:19)
    |
 18 | /             pixels.append(
 19 | |                 (r.round(), 80, b.round()),
   ...
 30 | |                 "test fail",
 31 | |             )
    | |_____________^

*/
ErrorInfo :: struct {
    context_start_lineno: u32,
    msg: string,
    filename: string,
    span: [4]u32, // ((row, col), (row, col))
    lines: []string,
    annotation: string,
}

print_error :: proc(err: ErrorInfo) {
    fmt.println("Error:", err.msg)
    fmt.printfln("    --> %s(%v:%v)", err.filename, err.span[0], err.span[1])

    // The size of the largest line number, plus 1 space of padding on either side
    gutter_size := digit_count(err.context_start_lineno + u32(len(err.lines))) + 2
    for _ in 0..<gutter_size {
        fmt.print(" ")
    }
    fmt.println("|")

    lineno := err.context_start_lineno
    for i in 0..<len(err.lines) {
        fmt.print(" ")
        for _ in 0..<(gutter_size - digit_count(lineno) - 2) {
            fmt.print(" ")
        }
        fmt.print(lineno)
        fmt.print(" | ")

        underline := false
        hook_under := false

        if err.span[0] == lineno {
            if err.span[0] == err.span[2] {
                underline = true
                fmt.print("  ")
            } else {
                fmt.print("/ ")
            }
        } else if err.span[0] < lineno && lineno <= err.span[2] {
            fmt.print("| ")
            if lineno == err.span[2] {
                hook_under = true
            }
        } else {
            fmt.print("  ")
        }

        fmt.println(err.lines[i])

        if underline {
            for _ in 0..<(gutter_size+3+err.span[1]) {
                fmt.print(" ")
            }
            for _ in 0..=(err.span[3] - err.span[1]) {
                fmt.print("^")
            }
            if len(err.annotation) != 0 {
                fmt.print("", err.annotation)
            }
            fmt.println()
        }

        if hook_under {
            for _ in 0..<(gutter_size) {
                fmt.print(" ")
            }
            fmt.print("| |")
            for _ in 0..<err.span[3] {
                fmt.print("_")
            }
            fmt.print("^")
            if len(err.annotation) != 0 {
                fmt.print("", err.annotation)
            }
            fmt.println()
        }

        lineno += 1
    }
}

digit_count :: proc(num: u32) -> u32 {
    num := u64(num)
    comp := u64(9)
    for count in 1..=9 {
        if num <= comp {
            return u32(count)
        }
        comp = comp * 10 + 9
    }
    return 10
}

// Generate a parse error for the next token
ts_token_parse_error_create :: proc(
    ts: ^TokenStream,
    ty: ParseErrorType,
    msg: string = "Could not parse input",
    annotation: string = "",
) -> ParseError {
    tk := ts_peek(ts)

    script := transmute(string)ts.script

    // With the exception of multiline string literals, tokens shouldn't cross
    // multiple rows
    row, start_col := human_row_col(ts.script, tk.pos)
    _, end_col := human_row_col(ts.script, tk.pos + tk.len - 1)

    lines := make([]string, 1, context.temp_allocator)
    lines[0] = strings.clone(
        strings.trim_right_space(
            script[
                byte_from_row_col(transmute([]byte)script, row, 1)
                :byte_from_row_col(transmute([]byte)script, row+1, 1)
            ]
        ),
        context.temp_allocator,
    )
    return ParseError {
        ty,
        ErrorInfo {
            row,
            msg,
            strings.clone("filename.todo", context.temp_allocator),
            {row, start_col, row, end_col},
            lines,
            annotation,
        }
    }
}

lex_error_create :: proc(
    data: []byte, idx: u32, filename: string, ty: LexErrorType, msg: string = "Unreadable input", annotation: string = "",
) -> LexError {
    script := transmute(string)data
    row, col := human_row_col(data, idx)
    lines := make([]string, 1, context.temp_allocator)
    lines[0] = strings.clone(
        strings.trim_right_space(
            script[
                byte_from_row_col(transmute([]byte)script, row, 1)
                :byte_from_row_col(transmute([]byte)script, row+1, 1)
            ]
        ),
        context.temp_allocator,
    )
    return LexError {
        ty,
        ErrorInfo {
            row,
            msg,
            strings.clone(filename, context.temp_allocator),
            {row, col, row, col},
            lines,
            annotation,
        }
    }
}

lex :: proc(filename: string) -> (ts: TokenStream, err: CompileError) {
    // Read the text and pad the end with 0's to avoid needing bounds checks
    // (just need a few extra bytes now, but SIMD may need more)
    data := read_entire_file_with_padding_from_path(filename, padding = 16) or_return
    defer if err != nil {
        delete(data)
    }

    // Check for ASCII
    for b, i in data {
        if b >= 127 {
            fmt.println("Hit invalid byte at index", i)
            err = lex_error_create(
                data,
                u32(i),
                filename,
                .NonAsciiData,
                "Invalid byte",
                "remove this byte",
            )
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

    newline := true
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
            append(&output, {ident_to_token_type(string(data[pos:i+1])), newline, pos, i-pos+1})
        } else if b == ',' {
            append(&output, {.Comma, newline, i, 1})
        } else if b == '=' {
            if data[i+1] == '=' {
                append(&output, {.DoubleEqual, newline, i, 2})
                i += 1
            } else {
                append(&output, {.Equal, newline, i, 1})
            }
        } else if b == '(' {
            append(&output, {.LBracket, newline, i, 1})
        } else if b == ')' {
            append(&output, {.RBracket, newline, i, 1})
        } else if b == '.' {
            append(&output, {.Dot, newline, i, 1})
        } else if b == '{' {
            append(&output, {.LCurly, newline, i, 1})
        } else if b == '}' {
            append(&output, {.RCurly, newline, i, 1})
        } else if b == '[' {
            append(&output, {.LSquare, newline, i, 1})
        } else if b == ']' {
            append(&output, {.RSquare, newline, i, 1})
        } else if '0' <= b && b <= '9' {
            pos := i
            for ;; i += 1 {
                b = data[i]
                if !('0' <= b && b <= '9') && b != '.' && b != 'e' && b != 'E' {
                    i -= 1
                    break
                }
            }
            append(&output, {.Number, newline, pos, i-pos+1})
        } else if b == '+' {
            if data[i+1] == '=' {
                append(&output, {.PlusEqual, newline, i, 2})
                i += 1
            } else {
                append(&output, {.Plus, newline, i, 1})
            }
        } else if b == '*' {
            if data[i+1] == '=' {
                append(&output, {.StarEqual, newline, i, 2})
                i += 1
            } else {
                append(&output, {.Star, newline, i, 1})
            }
        } else if b == '-' {
            if data[i+1] == '=' {
                append(&output, {.MinusEqual, newline, i, 2})
                i += 1
            } else {
                append(&output, {.Minus, newline, i, 1})
            }
        } else if b == ':' {
            append(&output, {.Colon, newline, i, 1})
        } else if b == ';' {
            append(&output, {.SemiColon, newline, i, 1})
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
                err = lex_error_create(
                    data,
                    pos,
                    filename,
                    .IncompleteString,
                    "String not closed",
                    "add `\"` to close the string",
                )
                return
            }
            append(&output, {.String, newline, pos, i-pos+1})
        } else if b == '!' {
            if data[i+1] == '=' {
                append(&output, {.BangEqual, newline, i, 2})
                i += 1
            } else {
                append(&output, {.Bang, newline, i, 1})
            }
        } else if b == '<' {
            if data[i+1] == '=' {
                append(&output, {.LAngleEqual, newline, i, 2})
                i += 1
            } else {
                append(&output, {.LAngle, newline, i, 1})
            }
        } else if b == '>' {
            if data[i+1] == '=' {
                append(&output, {.RAngleEqual, newline, i, 2})
                i += 1
            } else {
                append(&output, {.RAngle, newline, i, 1})
            }
        } else if b == '/' {
            if data[i+1] == '=' {
                append(&output, {.SlashEqual, newline, i, 2})
                i += 1
            } else if data[i+1] == '/' {
                // This is a comment, skip the rest of the line
                for ; data[i+1] != '\n' && data[i+1] != 0 ; i += 1 {}
            } else if data[i+1] == '*' {
                comment_start := i
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
                    err = lex_error_create(
                        data,
                        comment_start,
                        filename,
                        .IncompleteMultilineComment,
                        "Multiline comment not closed",
                        "add `*/` to close comment",
                    )
                    return
                }
            } else {
                append(&output, {.Slash, newline, i, 1})
            }
        } else if b == '%' {
            if data[i+1] == '=' {
                append(&output, {.PercentEqual, newline, i, 2})
                i += 1
            } else {
                append(&output, {.Percent, newline, i, 1})
            }
        } else {
            row, col := human_row_col(data, i)
            err = lex_error_create(data, i, filename, .InvalidTokenStart, "Unknown character not part of any token", "remove this character")
            return
        }
    }

    append(&output, {.End, false, u32(len(data)), u32(len(data))})
    append(&output, {.End, false, u32(len(data)), u32(len(data))})
    append(&output, {.End, false, u32(len(data)), u32(len(data))})
    append(&output, {.End, false, u32(len(data)), u32(len(data))})

    ts = {
        script = data,
        tokens = output[:],
        idx = 0,
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
