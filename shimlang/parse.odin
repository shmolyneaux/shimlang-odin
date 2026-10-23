package shimlang

import "core:fmt"

Module :: struct{
}

parse :: proc(ts: ^TokenStream) -> (Module, CompileError) {
    fmt.println("test")
    return {}, nil
}
