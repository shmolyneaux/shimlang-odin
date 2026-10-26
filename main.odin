package main

import "core:fmt"
import "core:os"
import "core:mem"

import "shimlang"

run :: proc() -> (res: bool, err: shimlang.CompileError) {
    ts := shimlang.lex("game.shm") or_return
    defer shimlang.token_stream_destroy(&ts)

    module := shimlang.parse(&ts) or_return
    defer shimlang.module_destroy(&module)

    fmt.println(module)

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
                    fmt.eprintf("- %v bytes @ %v %v\n", entry.size, entry.location, entry.memory)
                }
            }
            mem.tracking_allocator_destroy(&track)
        }
    }

    res, err := run()
    if err != nil {
        switch e in err {
        case shimlang.LexError:
            shimlang.print_error(e.info)
        case shimlang.ParseError:
            shimlang.print_error(e.info)
        case os.Error:
            fmt.println(e)
        }
    }
}
