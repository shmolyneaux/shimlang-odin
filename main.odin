package main

import "core:fmt"
import "core:os"
import "core:mem"

import "shimlang"

run :: proc() -> (res: bool, err: shimlang.CompileError) {
    ts := shimlang.lex("game.shm") or_return
    defer shimlang.token_stream_destroy(&ts)
    fmt.println(len(ts.tokens))

    //ast := parse(ts)

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
