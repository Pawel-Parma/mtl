# mtl
A small experimental compiler front-end written in Zig.

> [!important]  
> This project uses nominated zig versions  
> nominated version: 0.16.0-dev.368+2a97e0af6

## Build
1. Install the nominated zig version 
2. Build the project:
```bash
zig build
```

## Usage
```bash
zig build run -- [options] <file_path>
```

Options:
 - --help, -h          Print help message
 - --version, -v       Print version 
 - --debug, -d         Enable debug mode

When debug mode is enabled Tokens, AST and Scopes will be printed when available.  
\<file\_path\> is the entrypoint file.

## Example programs

1. Minimal empty program
Each entrypoint file requires a public main function.  
```mtl
pub fn main() void {

}
```
2. Variable declaration
```mtl
pub fn main() void {
    const a: u32 = 12;
    const b: f32 = 12.3;
    const int: type = i32;
    const c: int = 13;
    const d = 14;
    var e: int = 15 + c;
    var f := 16 + e * d;
}
```

3. Function declaration
```mtl
pub fn main() void {
    return add(1, 2);
}

fn add(a: u8, b: u8) u8 {
    return a + b;
}
```

