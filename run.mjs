import fs from 'node:fs';

let memory;

const text = (ptr, len) =>
    new TextDecoder().decode(new Uint8Array(memory.buffer, ptr >>> 0, len >>> 0));
const show = (x) => Object.is(x, -0) ? '-0' : String(x);

const env = {
    print_i32: (x) => console.log(show(x)),
    print: (ptr, len) => console.log(text(ptr, len)),
    write: (ptr, len) => process.stdout.write(text(ptr, len)),
    memory: new WebAssembly.Memory({ initial: 1 }),
}

const bytes = fs.readFileSync('test.wasm');
const { instance } = await WebAssembly.instantiate(bytes, {env});
memory = instance.exports.memory ?? env.memory;

const result = instance.exports.main();
if (result !== undefined) console.log([result].flat().map(show).join(' '));
